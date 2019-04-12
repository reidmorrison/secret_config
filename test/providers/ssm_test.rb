require_relative '../test_helper'

module Providers
  class SsmTest < Minitest::Test
    describe SecretConfig::Providers::Ssm do
      let :file_name do
        File.join(File.dirname(__FILE__), '..', 'config', 'application.yml')
      end

      let :root do
        "/development/connect"
      end

      let :expected do
        {
          "/development/connect/mongo/database"               => "secret_config_development",
          "/development/connect/mongo/primary"                => "127.0.0.1:27017",
          "/development/connect/mongo/secondary"              => "127.0.0.1:27018",
          "/development/connect/mysql/database"               => "secret_config_development",
          "/development/connect/mysql/password"               => "secret_configrules",
          "/development/connect/mysql/username"               => "secret_config",
          "/development/connect/mysql/host"                   => "127.0.0.1",
          "/development/connect/secrets/secret_key_base"      => "somereallylongstring",
          "/development/connect/symmetric_encryption/key"     => "QUJDREVGMTIzNDU2Nzg5MEFCQ0RFRjEyMzQ1Njc4OTA=",
          "/development/connect/symmetric_encryption/version" => "2",
          "/development/connect/symmetric_encryption/iv"      => "QUJDREVGMTIzNDU2Nzg5MA=="
        }
      end

      describe '#each' do
        it 'fetches all keys in path' do
          upload_settings if ENV['SECRETCONFIG_TEST_UPLOAD_SSM']

          ssm   = SecretConfig::Providers::Ssm.new
          paths = {}
          ssm.each(root) { |key, value| paths[key] = value }

          expected.each_pair do |key, value|
            assert_equal paths[key], value, "Path: #{key}"
          end
        end
      end

      def upload_settings
        file_provider = SecretConfig::Providers::File.new(file_name: file_name)
        ssm           = SecretConfig::Providers::Ssm.new
        file_provider.each(root) { |key, value| ap key; ssm.set(key, value) }
      end
    end
  end
end
