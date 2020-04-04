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
        h = SecretConfig::Utils.flatten(hash_registry, path = nil)
        assert_equal(flat_registry, h)
      end
    end
  end
end
