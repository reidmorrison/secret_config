require_relative '../test_helper'

module Providers
  class FileTest < Minitest::Test
    describe SecretConfig::Providers::File do
      let :file_name do
        File.join(File.dirname(__FILE__), '..', 'config', 'application.yml')
      end

      let :root do
        "/development/my_application"
      end

      let :expected do
        {
          "/development/my_application/mongo/database"               => "secret_config_development",
          "/development/my_application/mongo/primary"                => "127.0.0.1:27017",
          "/development/my_application/mongo/secondary"              => "127.0.0.1:27018",
          "/development/my_application/mysql/database"               => "secret_config_development",
          "/development/my_application/mysql/password"               => "secret_configrules",
          "/development/my_application/mysql/username"               => "secret_config",
          "/development/my_application/mysql/host"                   => "127.0.0.1",
          "/development/my_application/secrets/secret_key_base"      => "somereallylongstring",
          "/development/my_application/symmetric_encryption/key"     => "QUJDREVGMTIzNDU2Nzg5MEFCQ0RFRjEyMzQ1Njc4OTA=",
          "/development/my_application/symmetric_encryption/version" => 2,
          "/development/my_application/symmetric_encryption/iv"      => "QUJDREVGMTIzNDU2Nzg5MA=="
        }
      end

      describe '#each' do
        it 'file' do
          file_provider = SecretConfig::Providers::File.new(file_name: file_name)
          paths         = {}
          file_provider.each(root) { |key, value| paths[key] = value }

          expected.each_pair do |key, value|
            assert_equal value, paths[key], "Path: #{key}"
          end
        end
      end
    end
  end
end
