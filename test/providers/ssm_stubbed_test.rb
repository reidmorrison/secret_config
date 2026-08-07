require_relative "../test_helper"

# Exercises the SSM provider without touching AWS.
#
# `stub_responses` and `region` fall through `Providers::Ssm#initialize` into `Aws::SSM::Client`, so the
# client returns canned responses. The live round trip against a real parameter store stays in ssm_test.rb,
# which skips unless AWS credentials are present.
module Providers
  class SsmStubbedTest < Minitest::Test
    describe SecretConfig::Providers::Ssm do
      let :path do
        "/test/my_application"
      end

      let :provider do
        SecretConfig::Providers::Ssm.new(stub_responses: true, region: "us-east-1")
      end

      describe "#initialize" do
        it "uses the key id as supplied" do
          ssm = SecretConfig::Providers::Ssm.new(stub_responses: true, region: "us-east-1", key_id: "key-123")

          assert_equal "key-123", ssm.key_id
        end

        it "prefixes a bare key alias" do
          ssm = SecretConfig::Providers::Ssm.new(stub_responses: true, region: "us-east-1", key_alias: "my_key")

          assert_equal "alias/my_key", ssm.key_id
        end

        it "leaves an already prefixed key alias alone" do
          ssm = SecretConfig::Providers::Ssm.new(stub_responses: true, region: "us-east-1", key_alias: "alias/my_key")

          assert_equal "alias/my_key", ssm.key_id
        end

        it "prefers the key alias over the key id" do
          ssm = SecretConfig::Providers::Ssm.new(
            stub_responses: true, region: "us-east-1", key_id: "key-123", key_alias: "my_key"
          )

          assert_equal "alias/my_key", ssm.key_id
        end
      end

      describe "#each" do
        it "yields every parameter with its absolute key" do
          provider.client.stub_responses(
            :get_parameters_by_path,
            parameters: [
              {name: "#{path}/mysql/host", value: "127.0.0.1"},
              {name: "#{path}/mysql/database", value: "secret_config_test"}
            ],
            next_token: nil
          )

          paths = {}
          provider.each(path) { |key, value| paths[key] = value }

          expected = {
            "#{path}/mysql/host"     => "127.0.0.1",
            "#{path}/mysql/database" => "secret_config_test"
          }

          assert_equal expected, paths
        end

        it "follows the next token until the last page" do
          provider.client.stub_responses(
            :get_parameters_by_path,
            [
              {parameters: [{name: "#{path}/mysql/host", value: "127.0.0.1"}], next_token: "page-2"},
              {parameters: [{name: "#{path}/mysql/port", value: "3306"}], next_token: nil}
            ]
          )

          paths = {}
          provider.each(path) { |key, value| paths[key] = value }

          assert_equal({"#{path}/mysql/host" => "127.0.0.1", "#{path}/mysql/port" => "3306"}, paths)
        end

        it "retries when throttled" do
          # retry_max_ms of 1 keeps the backoff sleep at 0 seconds.
          throttled = SecretConfig::Providers::Ssm.new(
            stub_responses: true, region: "us-east-1", retry_max_ms: 1
          )
          throttled.client.stub_responses(
            :get_parameters_by_path,
            [
              "ThrottlingException",
              {parameters: [{name: "#{path}/mysql/host", value: "127.0.0.1"}], next_token: nil}
            ]
          )

          paths = {}
          throttled.each(path) { |key, value| paths[key] = value }

          assert_equal({"#{path}/mysql/host" => "127.0.0.1"}, paths)
        end

        it "raises once the retries are exhausted" do
          exhausted = SecretConfig::Providers::Ssm.new(
            stub_responses: true, region: "us-east-1", retry_count: 0, retry_max_ms: 1
          )
          exhausted.client.stub_responses(:get_parameters_by_path, "ThrottlingException")

          assert_raises Aws::SSM::Errors::ThrottlingException do
            exhausted.each(path) do |_key, _value|
              # Never reached, the throttling error is raised before the first parameter is yielded.
            end
          end
        end
      end

      describe "#set" do
        it "writes an encrypted parameter" do
          provider.client.stub_responses(:put_parameter, {})

          provider.set("#{path}/mysql/host", "127.0.0.1")

          request = provider.client.api_requests.last

          assert_equal :put_parameter, request[:operation_name]
          assert_equal "#{path}/mysql/host", request[:params][:name]
          assert_equal "127.0.0.1", request[:params][:value]
          assert_equal "SecureString", request[:params][:type]
          assert_equal "Intelligent-Tiering", request[:params][:tier]
          assert request[:params][:overwrite]
        end

        it "converts the value to a string" do
          provider.client.stub_responses(:put_parameter, {})

          provider.set("#{path}/symmetric_encryption/version", 2)

          assert_equal "2", provider.client.api_requests.last[:params][:value]
        end
      end

      describe "#delete" do
        it "deletes the parameter" do
          provider.client.stub_responses(:delete_parameter, {})

          provider.delete("#{path}/mysql/host")

          request = provider.client.api_requests.last

          assert_equal :delete_parameter, request[:operation_name]
          assert_equal "#{path}/mysql/host", request[:params][:name]
        end

        it "ignores a missing parameter" do
          provider.client.stub_responses(:delete_parameter, "ParameterNotFound")

          assert_nil provider.delete("#{path}/mysql/missing")
        end
      end

      describe "#fetch" do
        it "returns the decrypted value" do
          provider.client.stub_responses(:get_parameter, parameter: {name: "#{path}/mysql/host", value: "127.0.0.1"})

          assert_equal "127.0.0.1", provider.fetch("#{path}/mysql/host")
          assert provider.client.api_requests.last[:params][:with_decryption]
        end

        it "returns nil for a missing parameter" do
          provider.client.stub_responses(:get_parameter, "ParameterNotFound")

          assert_nil provider.fetch("#{path}/mysql/missing")
        end
      end

      describe "as a registry provider" do
        it "loads the registry from the parameter store" do
          provider.client.stub_responses(
            :get_parameters_by_path,
            parameters: [
              {name: "#{path}/mysql/host", value: "127.0.0.1"},
              {name: "#{path}/mongo/secondary", value: "${hostname}:27018"}
            ],
            next_token: nil
          )

          registry = SecretConfig::Registry.new(path: path, provider: provider)

          assert_equal "127.0.0.1", registry["mysql/host"]
          assert_equal "#{Socket.gethostname}:27018", registry["mongo/secondary"]
        end
      end
    end
  end
end
