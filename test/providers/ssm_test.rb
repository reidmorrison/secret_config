require_relative '../test_helper'

module Providers
  class SsmTest < Minitest::Test
    describe SecretConfig::Providers::Ssm do
      let :file_name do
        File.join(File.dirname(__FILE__), '..', 'config', 'application.yml')
      end

      let :path do
        "/test/my_application"
      end

      let :expected do
        {
          "/test/my_application/mongo/database"               => "secret_config_test",
          "/test/my_application/mongo/primary"                => "127.0.0.1:27017",
          "/test/my_application/mongo/secondary"              => "127.0.0.1:27018",
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
        unless ENV['AWS_ACCESS_KEY_ID']
          skip "Skipping AWS SSM Parameter Store tests because env var 'AWS_ACCESS_KEY_ID' is not defined."
        end
      end

      describe '#each' do
        it 'fetches all keys in path' do
          ssm   = SecretConfig::Providers::Ssm.new
          paths = {}
          ssm.each(path) { |key, value| paths[key] = value }

          if paths.empty?
            upload_settings(ssm) unless paths.key?("/test/my_application/mongo/database")
            ssm.each(path) { |key, value| paths[key] = value }
          end

          expected.each_pair do |key, value|
            assert_equal paths[key], value, "Path: #{key}"
          end
        end
      end

      def upload_settings(ssm)
        file_provider = SecretConfig::Providers::File.new(file_name: file_name)
        file_provider.each(path) { |key, value| ap key; ssm.set(key, value) }
      end
    end
  end
end
