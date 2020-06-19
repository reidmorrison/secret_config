require_relative "test_helper"
require "socket"

class RegistryTest < Minitest::Test
  describe SecretConfig::Registry do
    let :file_name do
      File.join(File.dirname(__FILE__), "config", "application.yml")
    end

    let :path do
      "/test/my_application"
    end

    let :provider do
      SecretConfig::Providers::File.new(file_name: file_name)
    end

    let :registry do
      SecretConfig::Registry.new(path: path, provider: provider)
    end

    let :expected do
      {
        "/test/my_application/mongo/database"               => "secret_config_test",
        "/test/my_application/mongo/primary"                => "127.0.0.1:27017",
        "/test/my_application/mongo/secondary"              => "#{Socket.gethostname}:27018",
        "/test/my_application/mysql/database"               => "secret_config_test",
        "/test/my_application/mysql/password"               => "secret_configrules",
        "/test/my_application/mysql/username"               => "secret_config",
        "/test/my_application/mysql/host"                   => "127.0.0.1",
        "/test/my_application/mysql/ports"                  => "12345,5343,26815",
        "/test/my_application/mysql/ports2"                 => "    12345, 5343 ,  26815",
        "/test/my_application/mysql/hostnames"              => "primary.example.net,secondary.example.net,backup.example.net",
        "/test/my_application/mysql/hostnames2"             => "   primary.example.net,  secondary.example.net ,  backup.example.net",
        "/test/my_application/secrets/secret_key_base"      => "somereallylongteststring",
        "/test/my_application/symmetric_encryption/key"     => "QUJDREVGMTIzNDU2Nzg5MEFCQ0RFRjEyMzQ1Njc4OTA=",
        "/test/my_application/symmetric_encryption/version" => "2",
        "/test/my_application/symmetric_encryption/iv"      => "QUJDREVGMTIzNDU2Nzg5MA=="
      }
    end

    describe "#configuration" do
      it "returns a copy of the config" do
        assert_equal "127.0.0.1", registry.configuration.dig("mysql", "host")
      end

      it "filters passwords" do
        assert_equal SecretConfig::FILTERED, registry.configuration.dig("mysql", "password")
      end

      it "filters key" do
        assert_equal SecretConfig::FILTERED, registry.configuration.dig("symmetric_encryption", "key")
      end
    end

    describe "#key?" do
      it "has key" do
        expected.each_pair do |key, _value|
          key = key.sub("#{path}/", "")
          assert registry.key?(key), "Path: #{key}"
        end
      end

      it "returns false with missing relative key" do
        refute registry.key?("invalid/path")
      end

      it "returns nil with missing full key" do
        refute registry.key?("/test/invalid/path")
      end
    end

    describe "#[]" do
      it "returns values" do
        expected.each_pair do |key, value|
          key = key.sub("#{path}/", "")
          assert_equal value, registry[key], "Path: #{key}"
        end
      end

      it "returns nil with missing relative key" do
        assert_nil registry["invalid/path"]
      end

      it "returns nil with missing full key" do
        assert_nil registry["/test/invalid/path"]
      end
    end

    describe "#fetch" do
      it "returns values" do
        expected.each_pair do |key, value|
          key = key.sub("#{path}/", "")
          assert_equal value, registry.fetch(key), "Path: #{key}"
        end
      end

      it "exception missing relative key" do
        assert_raises SecretConfig::MissingMandatoryKey do
          registry.fetch("invalid/path")
        end
      end

      it "returns nil with missing full key" do
        assert_raises SecretConfig::MissingMandatoryKey do
          registry.fetch("/test/invalid/path")
        end
      end

      it "returns default with missing key" do
        assert_equal "default_value", registry.fetch("/test/invalid/path", default: "default_value")
      end

      it "returns default with false value" do
        assert_equal false, registry.fetch("/test/invalid/path", default: false, type: :boolean)
      end

      it "converts to integer" do
        assert_equal 2, registry.fetch("symmetric_encryption/version", type: :integer)
      end

      describe "uses separator to extract an array" do
        it "of strings" do
          value = registry.fetch("mysql/hostnames", separator: ",")
          assert_equal ["primary.example.net", "secondary.example.net", "backup.example.net"], value
        end

        it "of strings with spaces" do
          value = registry.fetch("mysql/hostnames2", separator: ",")
          assert_equal ["primary.example.net", "secondary.example.net", "backup.example.net"], value
        end

        it "of integers" do
          value = registry.fetch("mysql/ports", type: :integer, separator: ",")
          assert_equal([12_345, 5343, 26_815], value)
        end

        it "of integers with spaces" do
          value = registry.fetch("mysql/ports2", type: :integer, separator: ",")
          assert_equal([12_345, 5343, 26_815], value)
        end

        it "accepts a default without requiring conversion" do
          value = registry.fetch("mysql/ports5", type: :integer, separator: ",", default: [23, 45, 72])
          assert_equal([23, 45, 72], value)
        end
      end

      it "decodes Base 64" do
        assert_equal "ABCDEF1234567890ABCDEF1234567890", registry.fetch("symmetric_encryption/key", encoding: :base64)
      end
    end
  end
end
