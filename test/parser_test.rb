require_relative "test_helper"
require "socket"

class ParserTest < Minitest::Test
  describe SecretConfig::Registry do
    let :file_name do
      File.join(File.dirname(__FILE__), "config", "application.yml")
    end

    let :path do
      "/test/other_application"
    end

    let :provider do
      SecretConfig::Providers::File.new(file_name: file_name)
    end

    let :registry do
      SecretConfig::Registry.new(path: path, provider: provider)
    end

    # let :parser do
    #   SecretConfig::Parser.new(path, registry)
    # end

    #
    # Retrieve values elsewhere in the registry.
    # Paths can be relative to the current root, or absolute paths outside the current root.
    #   %{fetch:key}      # Fetches a single value from a relative or absolute path
    # Return the value of the supplied key.
    #
    # With a relative key, look for the value in the current registry.
    # With an absolute key call the provider and fetch the value directly.
    #
    # Notes:
    # - A lot of absolute key lookups can be expensive since each one is a separate call.
    # def fetch(key)
    #   fetch_list[key] = key
    # end
    # describe "#fetch" do
    #   it "inside current path" do
    #
    #   end
    #
    #   it "outside current path" do
    #
    #   end
    # end

    #   %{import:path}    # Imports a path of keys and values into the current path
    # Replace the current value with a tree of values with the supplied path.
    #
    describe "#import" do
      it "removes import key" do
        refute registry.key?("symmetric_encryption/__import__"), -> { registry.configuration(filters: nil).ai }
      end

      it "retains overrides" do
        assert_equal "3", registry["symmetric_encryption/version"], -> { registry.configuration(filters: nil).ai }
        assert_equal "MTIzNDU2Nzg5MEFCQ0RFRg==", registry["symmetric_encryption/iv"]
      end

      it "retains child overrides" do
        assert_equal "key0", registry["symmetric_encryption/previous_key/key"], -> { registry.configuration(filters: nil).ai }
      end

      it "imports new fields" do
        assert_equal "QUJDREVGMTIzNDU2Nzg5MEFCQ0RFRjEyMzQ1Njc4OTA=", registry["symmetric_encryption/key"]
      end

      it "relative import empty" do
        assert_equal "secret_config_test", registry["mongo3/database"]
        assert_equal "localhost:27017", registry["mongo3/primary"]
      end

      it "relative import with overrides" do
        assert_equal "secret_config_test2", registry["mongo2/database"]
        assert_equal "localhost:27017", registry["mongo3/primary"]
      end
    end
  end
end
