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

    # `__import__` replaces its own key with a tree of values read from the supplied path.
    # The path can be relative to the current root, or an absolute path outside the current root.
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

    describe "#import resolution order" do
      let :file_name do
        File.join(File.dirname(__FILE__), "config", "imports.yml")
      end

      def registry_for(path)
        SecretConfig::Registry.new(path: path, provider: provider)
      end

      it "resolves an import of a node that is imported itself" do
        registry = registry_for("/test/forward")

        assert_equal "base.example.net", registry["mid/host"], -> { registry.configuration(filters: nil).ai }
        assert_equal "base.example.net", registry["top/host"]
      end

      it "retains overrides through a chain of imports" do
        registry = registry_for("/test/forward")

        assert_equal "5432", registry["mid/port"], -> { registry.configuration(filters: nil).ai }
        assert_equal "5432", registry["top/port"]
      end

      it "leaves no import key behind" do
        registry = registry_for("/test/forward")

        keys = SecretConfig::Utils.flatten(registry.configuration(filters: nil)).keys

        assert_empty keys.grep(/__import__/), -> { keys.ai }
      end

      it "raises for a circular import" do
        error = assert_raises SecretConfig::ConfigurationError do
          registry_for("/test/circular")
        end

        assert_includes error.message, "Circular __import__ in /test/circular"
      end

      it "raises for a node that imports itself" do
        error = assert_raises SecretConfig::ConfigurationError do
          registry_for("/test/self_referencing")
        end

        assert_includes error.message, "node/__import__"
      end

      describe "with absolute paths" do
        it "imports values from outside the current root" do
          registry = registry_for("/test/absolute_valid")

          assert_equal "source.example.net", registry["node/host"], -> { registry.configuration(filters: nil).ai }
        end

        it "retains overrides over the imported values" do
          registry = registry_for("/test/absolute_valid")

          assert_equal "5432", registry["node/port"], -> { registry.configuration(filters: nil).ai }
        end

        it "raises for two nodes that import each other" do
          error = assert_raises SecretConfig::ConfigurationError do
            registry_for("/test/absolute_a")
          end

          assert_includes error.message, "/test/absolute_a -> /test/absolute_b/node"
        end

        it "raises for a node that imports itself" do
          error = assert_raises SecretConfig::ConfigurationError do
            registry_for("/test/absolute_self")
          end

          assert_includes error.message, "/test/absolute_self/node -> /test/absolute_self/node"
        end
      end
    end
  end
end
