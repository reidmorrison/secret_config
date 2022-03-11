require_relative "test_helper"
require "socket"

class SecretConfigTest < Minitest::Test
  describe SecretConfig::Providers::File do
    let :file_name do
      File.join(File.dirname(__FILE__), "config", "application.yml")
    end

    let :path do
      "/test/my_application"
    end

    before do
      SecretConfig.use :file, path: path, file_name: file_name
    end

    describe ".configuration" do
      it "returns a copy of the config" do
        assert_equal "127.0.0.1", SecretConfig.configuration.dig("mysql", "host")
      end
    end

    describe ".key?" do
      it "has key" do
        assert SecretConfig.key?("mysql/database")
      end
    end

    describe ".[]" do
      it "returns values" do
        assert_equal "secret_config_test", SecretConfig["mysql/database"]
      end

      it "returns values with interpolation" do
        assert_equal "#{Socket.gethostname}:27018", SecretConfig["mongo/secondary"]
      end
    end

    describe ".fetch" do
      after do
        ENV["MYSQL_DATABASE"]      = nil
        SecretConfig.check_env_var = true
      end

      it "fetches values" do
        assert_equal "secret_config_test", SecretConfig.fetch("mysql/database")
      end

      it "fetches with default" do
        assert_equal "default", SecretConfig.fetch("mysql/unknown", default: "default")
      end

      it "fetches with default of nil" do
        assert_nil SecretConfig.fetch("mysql/unknown", default: nil)
      end

      it "can be overridden by an environment variable" do
        ENV["MYSQL_DATABASE"] = "other"

        SecretConfig.use :file, path: path, file_name: file_name
        assert_equal "other", SecretConfig.fetch("mysql/database")
      end

      it "returns values with interpolation" do
        assert_equal "#{Socket.gethostname}:27018", SecretConfig.fetch("mongo/secondary")
      end

      it "can be omitted an environment variable override with #check_env_var configuration" do
        ENV["MYSQL_DATABASE"] = "other"

        SecretConfig.check_env_var = false
        SecretConfig.use :file, path: path, file_name: file_name
        assert_equal "secret_config_test", SecretConfig.fetch("mysql/database")
      end
    end

    describe ".configure" do
      before do
        SecretConfig.use :file, path: path, file_name: file_name
      end

      it "#fetch" do
        database = nil
        SecretConfig.configure("mysql") do |config|
          database = config.fetch("database")
        end
        assert_equal "secret_config_test", database
      end

      it "#[]" do
        database = nil
        SecretConfig.configure("mysql") do |config|
          database = config["database"]
        end
        assert_equal "secret_config_test", database
      end

      it "#key?" do
        database = nil
        SecretConfig.configure("mysql") do |config|
          database = config.key?("database")
        end
        assert_equal true, database
      end
    end
  end
end
