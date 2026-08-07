require_relative "test_helper"

class UtilsTest < Minitest::Test
  describe SecretConfig::Utils do
    let :flat_registry do
      {
        "test/my_application/mysql/database"          => "secret_config_test",
        "test/my_application/mysql/password"          => "secret_configrules",
        "test/my_application/mysql/username"          => "secret_config",
        "test/my_application/mysql/host"              => "127.0.0.1",
        "test/my_application/secrets"                 => "both_a_path_and_a_value",
        "test/my_application/secrets/secret_key_base" => "somereallylongteststring"
      }
    end

    let :hash_registry do
      SecretConfig::Utils.hierarchical(flat_registry)
    end

    describe ".flatten" do
      it "returns a copy of the config" do
        h = SecretConfig::Utils.flatten(hash_registry, nil)
        assert_equal(flat_registry, h)
      end

      it "prefixes every key with the supplied path" do
        h = SecretConfig::Utils.flatten({"mysql" => {"host" => "127.0.0.1"}}, "/test")
        assert_equal({"/test/mysql/host" => "127.0.0.1"}, h)
      end
    end

    describe ".hierarchical" do
      it "expands a flat hash into a tree" do
        assert_equal "127.0.0.1", hash_registry.dig("test", "my_application", "mysql", "host")
      end

      it "stores a node that is both a value and a branch under the node key" do
        secrets = hash_registry.dig("test", "my_application", "secrets")

        assert_equal "both_a_path_and_a_value", secrets[SecretConfig::NODE_KEY]
        assert_equal "somereallylongteststring", secrets["secret_key_base"]
      end
    end

    describe ".decompose" do
      it "handles a key with no path" do
        assert_equal({"host" => "127.0.0.1"}, SecretConfig::Utils.decompose("host", "127.0.0.1"))
      end

      it "skips the empty segment of an absolute key" do
        assert_equal({"mysql" => {"host" => "127.0.0.1"}}, SecretConfig::Utils.decompose("/mysql/host", "127.0.0.1"))
      end

      it "merges into the supplied hash" do
        h = {"mysql" => {"host" => "127.0.0.1"}}
        SecretConfig::Utils.decompose("mysql/port", "3306", h)

        assert_equal({"mysql" => {"host" => "127.0.0.1", "port" => "3306"}}, h)
      end
    end

    describe ".constantize_symbol" do
      it "resolves a provider symbol to its class" do
        assert_equal SecretConfig::Providers::File, SecretConfig::Utils.constantize_symbol(:file)
        assert_equal SecretConfig::Providers::Ssm, SecretConfig::Utils.constantize_symbol(:ssm)
      end

      it "raises for an unknown provider" do
        error = assert_raises ArgumentError do
          SecretConfig::Utils.constantize_symbol(:not_a_provider)
        end
        assert_includes error.message, "SecretConfig::Providers::NotAProvider"
      end
    end

    describe ".camelize" do
      it "converts an underscored name" do
        assert_equal "NotAProvider", SecretConfig::Utils.camelize("not_a_provider")
      end

      it "converts a namespaced name" do
        assert_equal "SecretConfig::Providers", SecretConfig::Utils.camelize("secret_config/providers")
      end
    end
  end
end
