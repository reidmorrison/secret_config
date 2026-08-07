require_relative "../test_helper"

module Providers
  class FileTest < Minitest::Test
    describe SecretConfig::Providers::File do
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
          "/test/my_application/mongo/secondary"              => "${hostname}:27018",
          "/test/my_application/mysql/database"               => "secret_config_test",
          "/test/my_application/mysql/password"               => "secret_configrules",
          "/test/my_application/mysql/username"               => "secret_config",
          "/test/my_application/mysql/host"                   => "127.0.0.1",
          "/test/my_application/secrets/secret_key_base"      => "somereallylongteststring",
          "/test/my_application/symmetric_encryption/key"     => "QUJDREVGMTIzNDU2Nzg5MEFCQ0RFRjEyMzQ1Njc4OTA=",
          "/test/my_application/symmetric_encryption/version" => 2,
          "/test/my_application/symmetric_encryption/iv"      => "QUJDREVGMTIzNDU2Nzg5MA=="
        }
      end

      describe "#each" do
        it "file" do
          file_provider = SecretConfig::Providers::File.new(file_name: file_name)
          paths         = {}
          file_provider.each(path) { |key, value| paths[key] = value }

          expected.each_pair do |key, value|
            assert_equal value, paths[key], "Path: #{key}"
          end
        end

        it "raises a configuration error for a missing path" do
          file_provider = SecretConfig::Providers::File.new(file_name: file_name)

          error = assert_raises(SecretConfig::ConfigurationError) do
            file_provider.each("/test/missing") { nil }
          end

          assert_equal "Path /test/missing not found in file: #{file_name}", error.message
        end
      end

      describe "#fetch" do
        it "returns a value for the requested key" do
          file_provider = SecretConfig::Providers::File.new(file_name: file_name)

          assert_equal "127.0.0.1", file_provider.fetch("/test/my_application/mysql/host")
        end

        it "returns nil for a missing key or branch" do
          file_provider = SecretConfig::Providers::File.new(file_name: file_name)

          assert_nil file_provider.fetch("/test/my_application/missing")
          assert_nil file_provider.fetch("/test/my_application/mysql")
        end
      end
    end
  end
end
