require_relative "../test_helper"
require "tmpdir"

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

      # `set` and `delete` rewrite the file, so every test here works on its own temporary copy.
      describe "writes" do
        let :source do
          <<~YAML
            test:
              my_application:
                mysql:
                  host: 127.0.0.1
                  database: secret_config_test
          YAML
        end

        def with_file(contents)
          Dir.mktmpdir do |dir|
            path = File.join(dir, "application.yml")
            File.write(path, contents)
            yield SecretConfig::Providers::File.new(file_name: path), path
          end
        end

        describe "#set" do
          it "overwrites an existing key" do
            with_file(source) do |file_provider|
              assert_equal "localhost", file_provider.set("/test/my_application/mysql/host", "localhost")
              assert_equal "localhost", file_provider.fetch("/test/my_application/mysql/host")
              assert_equal "secret_config_test", file_provider.fetch("/test/my_application/mysql/database")
            end
          end

          it "creates the intermediate nodes for a new key" do
            with_file(source) do |file_provider|
              file_provider.set("/test/my_application/mongo/primary", "127.0.0.1:27017")

              assert_equal "127.0.0.1:27017", file_provider.fetch("/test/my_application/mongo/primary")
            end
          end

          it "stores the value under the node key when the key is already a node" do
            with_file(source) do |file_provider, path|
              file_provider.set("/test/my_application/mysql", "everything")

              assert_equal "everything", YAML.safe_load_file(path).dig("test", "my_application", "mysql", "__value__")
              assert_equal "127.0.0.1", file_provider.fetch("/test/my_application/mysql/host")
            end
          end

          it "converts a key that holds a value into a node" do
            with_file(source) do |file_provider|
              file_provider.set("/test/my_application/mysql/host/port", "3306")

              assert_equal "3306", file_provider.fetch("/test/my_application/mysql/host/port")
              assert_equal "127.0.0.1", file_provider.fetch("/test/my_application/mysql/host")
            end
          end

          it "raises rather than replacing ERB with its evaluated result" do
            with_file("test:\n  my_application:\n    mysql:\n      host: <%= 'localhost' %>\n") do |file_provider, path|
              error = assert_raises(SecretConfig::ConfigurationError) do
                file_provider.set("/test/my_application/mysql/database", "other")
              end

              assert_includes error.message, "Cannot write to config file containing ERB"
              assert_includes File.read(path), "<%="
            end
          end
        end

        describe "#delete" do
          it "removes the key" do
            with_file(source) do |file_provider|
              assert_nil file_provider.delete("/test/my_application/mysql/host")
              assert_nil file_provider.fetch("/test/my_application/mysql/host")
              assert_equal "secret_config_test", file_provider.fetch("/test/my_application/mysql/database")
            end
          end

          it "prunes the nodes that the delete leaves empty" do
            with_file(source) do |file_provider, path|
              file_provider.delete("/test/my_application/mysql/host")
              file_provider.delete("/test/my_application/mysql/database")

              assert_empty YAML.safe_load_file(path)
            end
          end

          it "keeps the children when the key is also a node" do
            with_file(source) do |file_provider, path|
              file_provider.set("/test/my_application/mysql", "everything")
              file_provider.delete("/test/my_application/mysql")

              assert_equal "127.0.0.1", file_provider.fetch("/test/my_application/mysql/host")
              refute YAML.safe_load_file(path).dig("test", "my_application", "mysql").key?("__value__")
            end
          end

          it "leaves the file alone for a missing key" do
            with_file(source) do |file_provider, path|
              assert_nil file_provider.delete("/test/my_application/mysql/missing")
              assert_nil file_provider.delete("/test/missing/branch")

              assert_equal source, File.read(path)
            end
          end
        end
      end
    end
  end
end
