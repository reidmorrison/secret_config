require_relative "../test_helper"

# Exercises the Secrets Manager provider without touching AWS.
#
# `stub_responses` and `region` fall through `Providers::SecretsManager#initialize` into
# `Aws::SecretsManager::Client`, so the client returns canned responses. There is no live counterpart
# to this file: unlike the Parameter Store, every secret created by a round trip would be billed for a
# month and could not be deleted outright, so the whole provider is covered here.
module Providers
  class SecretsManagerStubbedTest < Minitest::Test
    describe SecretConfig::Providers::SecretsManager do
      let :path do
        "/test/my_application"
      end

      let :provider do
        SecretConfig::Providers::SecretsManager.new(stub_responses: true, region: "us-east-1")
      end

      describe "#initialize" do
        it "uses the key id as supplied" do
          manager = SecretConfig::Providers::SecretsManager.new(
            stub_responses: true, region: "us-east-1", key_id: "key-123"
          )

          assert_equal "key-123", manager.key_id
        end

        it "prefixes a bare key alias" do
          manager = SecretConfig::Providers::SecretsManager.new(
            stub_responses: true, region: "us-east-1", key_alias: "my_key"
          )

          assert_equal "alias/my_key", manager.key_id
        end

        it "leaves an already prefixed key alias alone" do
          manager = SecretConfig::Providers::SecretsManager.new(
            stub_responses: true, region: "us-east-1", key_alias: "alias/my_key"
          )

          assert_equal "alias/my_key", manager.key_id
        end

        it "prefers the key alias over the key id" do
          manager = SecretConfig::Providers::SecretsManager.new(
            stub_responses: true, region: "us-east-1", key_id: "key-123", key_alias: "my_key"
          )

          assert_equal "alias/my_key", manager.key_id
        end

        it "defaults to the longest recovery window" do
          assert_equal 30, provider.recovery_window_in_days
        end

        it "accepts a recovery window within the supported range" do
          manager = SecretConfig::Providers::SecretsManager.new(
            stub_responses: true, region: "us-east-1", recovery_window_in_days: 7
          )

          assert_equal 7, manager.recovery_window_in_days
        end

        it "rejects a recovery window that Secrets Manager would refuse" do
          error = assert_raises ArgumentError do
            SecretConfig::Providers::SecretsManager.new(
              stub_responses: true, region: "us-east-1", recovery_window_in_days: 1
            )
          end

          assert_includes error.message, "recovery_window_in_days must be between 7 and 30"
        end
      end

      describe "#each" do
        it "yields every secret with its absolute key" do
          provider.client.stub_responses(
            :batch_get_secret_value,
            secret_values: [
              {name: "#{path}/mysql/host", secret_string: "127.0.0.1"},
              {name: "#{path}/mysql/database", secret_string: "secret_config_test"}
            ],
            errors:        [],
            next_token:    nil
          )

          paths = {}
          provider.each(path) { |key, value| paths[key] = value }

          expected = {
            "#{path}/mysql/host"     => "127.0.0.1",
            "#{path}/mysql/database" => "secret_config_test"
          }

          assert_equal expected, paths
        end

        it "filters by name prefix, in pages" do
          provider.each(path) { |_key, _value| nil }

          request = provider.client.api_requests.last

          assert_equal :batch_get_secret_value, request[:operation_name]
          assert_equal [{key: "name", values: [path]}], request[:params][:filters]
          assert_equal 20, request[:params][:max_results]
        end

        it "follows the next token until the last page" do
          provider.client.stub_responses(
            :batch_get_secret_value,
            [
              {secret_values: [{name: "#{path}/mysql/host", secret_string: "127.0.0.1"}], next_token: "page-2"},
              {secret_values: [{name: "#{path}/mysql/port", secret_string: "3306"}], next_token: nil}
            ]
          )

          paths = {}
          provider.each(path) { |key, value| paths[key] = value }

          assert_equal({"#{path}/mysql/host" => "127.0.0.1", "#{path}/mysql/port" => "3306"}, paths)
        end

        # The name filter is a plain string prefix, so a sibling path that starts with the same
        # characters comes back from AWS and has to be discarded here.
        it "skips names that only share a prefix with the path" do
          provider.client.stub_responses(
            :batch_get_secret_value,
            secret_values: [
              {name: "#{path}/mysql/host", secret_string: "127.0.0.1"},
              {name: "#{path}_other/mysql/host", secret_string: "10.0.0.1"},
              {name: path, secret_string: "not a setting"}
            ],
            next_token:    nil
          )

          paths = {}
          provider.each(path) { |key, value| paths[key] = value }

          assert_equal({"#{path}/mysql/host" => "127.0.0.1"}, paths)
        end

        it "skips binary secrets, which have no string value" do
          provider.client.stub_responses(
            :batch_get_secret_value,
            secret_values: [
              {name: "#{path}/mysql/host", secret_string: "127.0.0.1"},
              {name: "#{path}/keystore", secret_binary: "\x01\x02"}
            ],
            next_token:    nil
          )

          paths = {}
          provider.each(path) { |key, value| paths[key] = value }

          assert_equal({"#{path}/mysql/host" => "127.0.0.1"}, paths)
        end

        it "raises when a secret could not be read" do
          provider.client.stub_responses(
            :batch_get_secret_value,
            secret_values: [{name: "#{path}/mysql/host", secret_string: "127.0.0.1"}],
            errors:        [
              {secret_id: "#{path}/mysql/password", error_code: "AccessDeniedException", message: "Denied"}
            ],
            next_token:    nil
          )

          error = assert_raises SecretConfig::ConfigurationError do
            provider.each(path) { |_key, _value| nil }
          end

          assert_includes error.message, "Failed to read 1 secret(s) under #{path}"
          assert_includes error.message, "#{path}/mysql/password: AccessDeniedException Denied"
        end
      end

      describe "#set" do
        it "updates an existing secret" do
          provider.client.stub_responses(:update_secret, {})

          provider.set("#{path}/mysql/host", "127.0.0.1")

          request = provider.client.api_requests.last

          assert_equal :update_secret, request[:operation_name]
          assert_equal "#{path}/mysql/host", request[:params][:secret_id]
          assert_equal "127.0.0.1", request[:params][:secret_string]
        end

        it "creates the secret when it does not exist yet" do
          provider.client.stub_responses(:update_secret, "ResourceNotFoundException")
          provider.client.stub_responses(:create_secret, {})

          provider.set("#{path}/mysql/host", "127.0.0.1")

          request = provider.client.api_requests.last

          assert_equal :create_secret, request[:operation_name]
          assert_equal "#{path}/mysql/host", request[:params][:name]
          assert_equal "127.0.0.1", request[:params][:secret_string]
        end

        it "encrypts with the supplied KMS key" do
          manager = SecretConfig::Providers::SecretsManager.new(
            stub_responses: true, region: "us-east-1", key_alias: "my_key"
          )
          manager.client.stub_responses(:update_secret, {})

          manager.set("#{path}/mysql/host", "127.0.0.1")

          assert_equal "alias/my_key", manager.client.api_requests.last[:params][:kms_key_id]
        end

        it "converts the value to a string" do
          provider.client.stub_responses(:update_secret, {})

          provider.set("#{path}/symmetric_encryption/version", 2)

          assert_equal "2", provider.client.api_requests.last[:params][:secret_string]
        end
      end

      describe "#delete" do
        it "schedules the secret for deletion" do
          provider.client.stub_responses(:delete_secret, {})

          provider.delete("#{path}/mysql/host")

          request = provider.client.api_requests.last

          assert_equal :delete_secret, request[:operation_name]
          assert_equal "#{path}/mysql/host", request[:params][:secret_id]
          assert_equal 30, request[:params][:recovery_window_in_days]
        end

        it "uses the configured recovery window" do
          manager = SecretConfig::Providers::SecretsManager.new(
            stub_responses: true, region: "us-east-1", recovery_window_in_days: 7
          )
          manager.client.stub_responses(:delete_secret, {})

          manager.delete("#{path}/mysql/host")

          assert_equal 7, manager.client.api_requests.last[:params][:recovery_window_in_days]
        end

        it "ignores a missing secret" do
          provider.client.stub_responses(:delete_secret, "ResourceNotFoundException")

          assert_nil provider.delete("#{path}/mysql/missing")
        end
      end

      describe "#fetch" do
        it "returns the decrypted value" do
          provider.client.stub_responses(
            :get_secret_value, name: "#{path}/mysql/host", secret_string: "127.0.0.1"
          )

          assert_equal "127.0.0.1", provider.fetch("#{path}/mysql/host")
          assert_equal "#{path}/mysql/host", provider.client.api_requests.last[:params][:secret_id]
        end

        it "returns nil for a missing secret" do
          provider.client.stub_responses(:get_secret_value, "ResourceNotFoundException")

          assert_nil provider.fetch("#{path}/mysql/missing")
        end
      end

      describe "as a registry provider" do
        it "loads the registry from secrets manager" do
          provider.client.stub_responses(
            :batch_get_secret_value,
            secret_values: [
              {name: "#{path}/mysql/host", secret_string: "127.0.0.1"},
              {name: "#{path}/mongo/secondary", secret_string: "${hostname}:27018"}
            ],
            next_token:    nil
          )

          registry = SecretConfig::Registry.new(path: path, provider: provider)

          assert_equal "127.0.0.1", registry["mysql/host"]
          assert_equal "#{Socket.gethostname}:27018", registry["mongo/secondary"]
        end
      end
    end
  end
end
