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

      describe "with an environment variable override" do
        before do
          ENV["MYSQL_UNKNOWN"] = "from_env"
        end

        after do
          ENV["MYSQL_UNKNOWN"]       = nil
          SecretConfig.check_env_var = true
        end

        it "has a key that is only present as an environment variable" do
          assert registry.key?("mysql/unknown")
        end

        it "returns the same answer before and after the key has been read" do
          assert registry.key?("mysql/unknown")
          assert_equal "from_env", registry["mysql/unknown"]
          assert registry.key?("mysql/unknown")
        end

        it "does not add the key to the configuration when it is read" do
          assert_equal "from_env", registry["mysql/unknown"]

          assert_nil registry.configuration.dig("mysql", "unknown")
        end

        it "returns false when environment variable checking is disabled" do
          SecretConfig.check_env_var = false

          refute registry.key?("mysql/unknown")
        end
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
        refute registry.fetch("/test/invalid/path", default: false, type: :boolean)
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

      it "passes the value through for an unrecognized encoding" do
        assert_equal "2", registry.fetch("symmetric_encryption/version", encoding: :unknown)
      end

      it "converts to float" do
        assert_in_delta 0.25, registry.fetch("mysql/unknown", default: "0.25", type: :float)
      end

      it "converts to symbol" do
        assert_equal :info, registry.fetch("mysql/unknown", default: "info", type: :symbol)
      end

      it "converts a blank value to nil when converting to symbol" do
        assert_nil registry.fetch("mysql/unknown", default: "  ", type: :symbol)
      end

      it "converts to json" do
        assert_equal({"a" => 1}, registry.fetch("mysql/unknown", default: '{"a":1}', type: :json))
      end

      it "returns nil when converting a nil default to json" do
        assert_nil registry.fetch("mysql/unknown", default: nil, type: :json)
      end

      it "raises for an unrecognized type" do
        error = assert_raises ArgumentError do
          registry.fetch("mysql/unknown", default: "value", type: :array)
        end
        assert_equal "Unrecognized type:array", error.message
      end

      # NOTE: a block is only consulted when a default is also supplied, since the missing key check
      # runs first. See TECH_DEBT.md.
      it "prefers a block over the supplied default when the key is missing" do
        assert_equal "from_block", registry.fetch("mysql/unknown", default: "unused") { "from_block" }
      end

      it "raises when a block is supplied without a default" do
        assert_raises SecretConfig::MissingMandatoryKey do
          registry.fetch("mysql/unknown") { "from_block" }
        end
      end
    end

    describe "writing" do
      let :provider do
        InMemoryProvider.new(
          "/test/my_application/mysql/database" => "secret_config_test",
          "/test/my_application/mysql/host"     => "127.0.0.1"
        )
      end

      describe "#set" do
        it "writes through to the provider using the absolute key" do
          registry.set("mysql/username", "secret_config")

          assert_equal "secret_config", provider.hash["/test/my_application/mysql/username"]
          assert_equal "secret_config", registry["mysql/username"]
        end

        it "does not expand a key that is already absolute" do
          registry.set("/other_application/mysql/username", "other")

          assert_equal "other", provider.hash["/other_application/mysql/username"]
        end

        it "is aliased by #[]=" do
          registry["mysql/username"] = "via_brackets"

          assert_equal "via_brackets", provider.hash["/test/my_application/mysql/username"]
        end
      end

      describe "#delete" do
        it "removes the key from the provider and the cache" do
          registry.delete("mysql/host")

          refute provider.hash.key?("/test/my_application/mysql/host")
          refute registry.key?("mysql/host")
        end
      end

      describe "#refresh!" do
        it "picks up keys added to the provider" do
          refute registry.key?("mysql/port")
          provider.set("/test/my_application/mysql/port", "3306")

          registry.refresh!

          assert_equal "3306", registry["mysql/port"]
        end

        it "drops keys removed from the provider" do
          assert registry.key?("mysql/host")
          provider.delete("/test/my_application/mysql/host")

          registry.refresh!

          refute registry.key?("mysql/host")
        end
      end
    end

    describe "path resolution" do
      it "prefixes a relative path with a slash" do
        registry = SecretConfig::Registry.new(path: "test/my_application", provider: provider)

        assert_equal "/test/my_application", registry.path
      end

      it "raises when no path can be determined" do
        original_path = ENV.fetch("SECRET_CONFIG_PATH", nil)
        original_env  = ENV.fetch("RAILS_ENV", nil)
        ENV["SECRET_CONFIG_PATH"] = nil
        ENV["RAILS_ENV"]          = nil

        assert_raises SecretConfig::UndefinedRootError do
          SecretConfig::Registry.new(provider: provider)
        end
      ensure
        ENV["SECRET_CONFIG_PATH"] = original_path
        ENV["RAILS_ENV"]          = original_env
      end

      it "reads the path from SECRET_CONFIG_PATH" do
        original_path             = ENV.fetch("SECRET_CONFIG_PATH", nil)
        ENV["SECRET_CONFIG_PATH"] = "/test/my_application"

        assert_equal "/test/my_application", SecretConfig::Registry.new(path: "/ignored", provider: provider).path
      ensure
        ENV["SECRET_CONFIG_PATH"] = original_path
      end
    end
  end
end
