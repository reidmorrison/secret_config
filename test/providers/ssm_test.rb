require_relative "../test_helper"

module Providers
  class SsmTest < Minitest::Test
    describe SecretConfig::Providers::Ssm do
      let :file_name do
        File.join(File.dirname(__FILE__), "..", "config", "application.yml")
      end

      let :path do
        "/test/my_application"
      end

      let :expected do
        {
          "/test/my_application/mongo/database"               => "secret_config_test",
          "/test/my_application/mongo/primary"                => "127.0.0.1:27017",
          "/test/my_application/mongo/secondary"              => "%{hostname}:27018",
          "/test/my_application/mysql/database"               => "secret_config_test",
          "/test/my_application/mysql/password"               => "secret_configrules",
          "/test/my_application/mysql/username"               => "secret_config",
          "/test/my_application/mysql/host"                   => "127.0.0.1",
          "/test/my_application/secrets/secret_key_base"      => "somereallylongteststring",
          "/test/my_application/symmetric_encryption/key"     => "QUJDREVGMTIzNDU2Nzg5MEFCQ0RFRjEyMzQ1Njc4OTA=",
          "/test/my_application/symmetric_encryption/version" => "2",
          "/test/my_application/symmetric_encryption/iv"      => "QUJDREVGMTIzNDU2Nzg5MA=="
        }
      end

      before do
        unless ENV["AWS_ACCESS_KEY_ID"]
          skip "Skipping AWS SSM Parameter Store tests because env var 'AWS_ACCESS_KEY_ID' is not defined."
        end
      end

      describe "#each" do
        let :ssm_provider do
          SecretConfig::Providers::Ssm.new
        end

        let :ssm_extended_provider do
          SecretConfig::Providers::Ssm.new(credentials: ::Aws::AssumeRoleCredentials.new(
            role_arn:          "arn:aws:iam::#{ENV['SECRET_CONFIG_ACCOUNT_ID']}:role/secret_config_test",
            role_session_name: "SecretConfigSession-#{SecureRandom.uuid}"
          ))
        end

        def fill_paths(provider)
          paths = {}

          provider.each(path) { |key, value| paths[key] = value }

          upload_settings(provider) if paths.empty?

          paths
        end

        it "fetches all keys in path" do
          paths = fill_paths(ssm_provider)

          expected.each_pair do |key, value|
            assert_equal paths[key], value, "Path: #{key}"
          end
        end

        it "provider with extended credentials fetches all keys in path" do
          paths = fill_paths(ssm_extended_provider)

          expected.each_pair do |key, value|
            assert_equal paths[key], value, "Path: #{key}"
          end
        end
      end

      def upload_settings(ssm)
        file_provider = SecretConfig::Providers::File.new(file_name: file_name)
        file_provider.each(path) do |key, value|
          ap key
          ssm.set(key, value)
        end
      end
    end
  end
end
