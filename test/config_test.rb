require_relative "test_helper"

class ConfigTest < Minitest::Test
  describe SecretConfig::Config do
    let :provider do
      InMemoryProvider.new(
        "/test/my_application/mysql/database" => "secret_config_test",
        "/test/my_application/mysql/host"     => "127.0.0.1"
      )
    end

    let :registry do
      SecretConfig::Registry.new(path: "/test/my_application", provider: provider)
    end

    let :config do
      SecretConfig::Config.new("mysql", registry)
    end

    describe "#initialize" do
      it "raises when the path is nil" do
        assert_raises ArgumentError do
          SecretConfig::Config.new(nil, registry)
        end
      end
    end

    describe "#fetch" do
      it "joins the sub path onto the configured path" do
        assert_equal "secret_config_test", config.fetch("database")
      end

      it "passes options through to the registry" do
        assert_equal 3306, config.fetch("port", default: "3306", type: :integer)
      end
    end

    describe "#[]" do
      it "returns the value" do
        assert_equal "127.0.0.1", config["host"]
      end

      it "returns nil for a missing key" do
        assert_nil config["unknown"]
      end
    end

    describe "#[]=" do
      it "writes through to the provider using the fully expanded key" do
        config["password"] = "secret_configrules"

        assert_equal "secret_configrules", provider.hash["/test/my_application/mysql/password"]
        assert_equal "secret_configrules", config["password"]
      end
    end

    describe "#set" do
      it "writes through to the provider using the fully expanded key" do
        config.set("username", "secret_config")

        assert_equal "secret_config", provider.hash["/test/my_application/mysql/username"]
        assert_equal "secret_config", config["username"]
      end
    end

    describe "#delete" do
      it "removes the key from the provider" do
        config.delete("host")

        refute provider.hash.key?("/test/my_application/mysql/host")
        refute config.key?("host")
      end
    end

    describe "#key?" do
      it "returns true for a present key" do
        assert config.key?("database")
      end

      it "returns false for a missing key" do
        refute config.key?("unknown")
      end
    end

    describe "nil sub paths" do
      it "raises for every accessor" do
        assert_raises(ArgumentError) { config.fetch(nil) }
        assert_raises(ArgumentError) { config[nil] }
        assert_raises(ArgumentError) { config[nil] = "value" }
        assert_raises(ArgumentError) { config.key?(nil) }
        assert_raises(ArgumentError) { config.set(nil, "value") }
        assert_raises(ArgumentError) { config.delete(nil) }
      end
    end

    describe "delegation" do
      it "#configuration returns the whole registry, not just this path" do
        assert_equal "127.0.0.1", config.configuration.dig("mysql", "host")
      end

      it "#refresh! reloads from the provider" do
        provider.set("/test/my_application/mysql/port", "3306")

        config.refresh!

        assert_equal "3306", config["port"]
      end
    end
  end
end
