require_relative "test_helper"
require "tmpdir"
require "fileutils"

# Covers argument parsing, and the command implementations that the file provider makes reachable
# without AWS credentials. `--console` and the SSM-specific paths are still not exercised here.
class CLITest < Minitest::Test
  describe SecretConfig::CLI do
    describe "#initialize" do
      it "defaults to the ssm provider" do
        assert_equal :ssm, SecretConfig::CLI.new(["--version"]).provider
      end

      it "defaults the random size to 32" do
        assert_equal 32, SecretConfig::CLI.new(["--version"]).random_size
      end

      it "prints the help and exits when no arguments are supplied" do
        out, = capture_io do
          error = assert_raises(SystemExit) { SecretConfig::CLI.new([]) }
          assert_equal(-10, error.status)
        end

        assert_includes out, "secret-config [options]"
      end

      it "prints the help and exits for --help" do
        out, = capture_io do
          assert_raises(SystemExit) { SecretConfig::CLI.new(["--help"]) }
        end

        assert_includes out, "Prints this help."
      end
    end

    describe "operations" do
      it "parses --export" do
        assert_equal "/production/my_application", SecretConfig::CLI.new(["--export", "/production/my_application"]).export
      end

      it "parses --import" do
        assert_equal "/production/my_application", SecretConfig::CLI.new(["--import", "/production/my_application"]).import
      end

      it "parses --diff" do
        assert_equal "/production/my_application", SecretConfig::CLI.new(["--diff", "/production/my_application"]).diff
      end

      it "parses --delete" do
        assert_equal "mysql/host", SecretConfig::CLI.new(["--delete", "mysql/host"]).delete_key
      end

      it "parses --delete-tree" do
        assert_equal "/production/my_application", SecretConfig::CLI.new(["--delete-tree", "/production/my_application"]).delete_tree
      end

      it "parses --fetch" do
        assert_equal "mysql/host", SecretConfig::CLI.new(["--fetch", "mysql/host"]).fetch_key
      end

      it "parses --console" do
        assert SecretConfig::CLI.new(["--console"]).console
      end

      it "parses --version" do
        assert SecretConfig::CLI.new(["--version"]).show_version
      end
    end

    describe "--set" do
      it "splits the key from the value" do
        cli = SecretConfig::CLI.new(["--set", "mysql/database=localhost"])

        assert_equal "mysql/database", cli.set_key
        assert_equal "localhost", cli.set_value
      end

      it "raises when no value is supplied" do
        assert_raises ArgumentError do
          SecretConfig::CLI.new(["--set", "mysql/database"])
        end
      end

      it "raises when the value is empty" do
        assert_raises ArgumentError do
          SecretConfig::CLI.new(["--set", "mysql/database="])
        end
      end

      it "retains an equals sign in the value" do
        cli = SecretConfig::CLI.new(["--set", "symmetric_encryption/key=QUJDREVG12345="])

        assert_equal "symmetric_encryption/key", cli.set_key
        assert_equal "QUJDREVG12345=", cli.set_value
      end

      it "retains every equals sign in the value" do
        cli = SecretConfig::CLI.new(["--set", "mysql/url=host=localhost;port=3306"])

        assert_equal "mysql/url", cli.set_key
        assert_equal "host=localhost;port=3306", cli.set_value
      end
    end

    describe "modifiers" do
      it "parses --path" do
        assert_equal "/production/my_application", SecretConfig::CLI.new(["--path", "/production/my_application"]).path
      end

      it "parses --file" do
        assert_equal "application.yml", SecretConfig::CLI.new(["--file", "application.yml"]).file_name
      end

      it "parses --provider" do
        assert_equal :file, SecretConfig::CLI.new(["--provider", "file"]).provider
        assert_equal :secrets_manager, SecretConfig::CLI.new(["--provider", "secrets_manager"]).provider
      end

      it "parses --no-filter" do
        assert SecretConfig::CLI.new(["--no-filter"]).no_filter
      end

      it "parses --interpolate" do
        assert SecretConfig::CLI.new(["--interpolate"]).interpolate
      end

      it "parses --prune" do
        assert SecretConfig::CLI.new(["--prune"]).prune
      end

      it "parses --force" do
        assert SecretConfig::CLI.new(["--force"]).force
      end

      it "parses --key_id" do
        assert_equal "key-123", SecretConfig::CLI.new(["--key_id", "key-123"]).key_id
      end

      it "parses --key_alias" do
        assert_equal "my_key", SecretConfig::CLI.new(["--key_alias", "my_key"]).key_alias
      end

      it "coerces --random_size to an integer" do
        cli = nil
        capture_io { cli = SecretConfig::CLI.new(["--random_size", "64"]) }

        assert_equal 64, cli.random_size
      end

      it "warns that --random_size is deprecated, pointing at the per-key form" do
        SecretConfig.instance_variable_set(:@deprecation_warnings, Set.new)
        _, err = capture_io { SecretConfig::CLI.new(["--random_size", "64"]) }

        assert_includes err, "Deprecation"
        assert_includes err, "--random_size"
        assert_includes err, "__generate__:64"
      end

      it "does not warn when --random_size is not supplied" do
        SecretConfig.instance_variable_set(:@deprecation_warnings, Set.new)
        _, err = capture_io { SecretConfig::CLI.new(["--version"]) }

        assert_empty err
      end

      it "defaults the filter and interpolation flags to off" do
        cli = SecretConfig::CLI.new(["--version"])

        refute cli.no_filter
        refute cli.interpolate
        refute cli.prune
        refute cli.force
      end
    end

    # "-f" is the short form of --fetch only. --file is deliberately long form only, since defining
    # "-f" on both silently gave --fetch the short option and left --file without one.
    describe "the -f short option" do
      it "sets the fetch key" do
        cli = SecretConfig::CLI.new(["-f", "mysql/host"])

        assert_equal "mysql/host", cli.fetch_key
        assert_nil cli.file_name
      end

      it "leaves --file with a long form only" do
        cli = SecretConfig::CLI.new(["--file", "application.yml", "-f", "mysql/host"])

        assert_equal "application.yml", cli.file_name
        assert_equal "mysql/host", cli.fetch_key
      end
    end

    describe "#provider_instance" do
      it "builds the file provider" do
        cli      = SecretConfig::CLI.new(["--provider", "file", "--provider-file", "test/config/application.yml"])
        instance = cli.send(:provider_instance)

        assert_instance_of SecretConfig::Providers::File, instance
        assert_equal "test/config/application.yml", instance.file_name
      end

      it "falls back to the env var, then the default, for the file provider" do
        original = ENV.fetch("SECRET_CONFIG_FILE_NAME", nil)

        ENV["SECRET_CONFIG_FILE_NAME"] = "from_env.yml"
        cli = SecretConfig::CLI.new(["--provider", "file"])

        assert_equal "from_env.yml", cli.send(:provider_instance).file_name

        ENV["SECRET_CONFIG_FILE_NAME"] = nil
        cli = SecretConfig::CLI.new(["--provider", "file"])

        assert_equal "config/application.yml", cli.send(:provider_instance).file_name
      ensure
        ENV["SECRET_CONFIG_FILE_NAME"] = original
      end

      it "raises for an unknown provider" do
        cli = SecretConfig::CLI.new(["--provider", "vault", "--fetch", "mysql/host"])

        error = assert_raises ArgumentError do
          cli.send(:provider_instance)
        end
        assert_equal "Invalid provider: vault. Valid providers: ssm | secrets_manager | file", error.message
      end
    end

    # The KMS key the AWS providers are built with. Neither of those providers can be constructed here,
    # since both need credentials, so what they would be handed is asserted on directly.
    describe "#kms_args" do
      it "is empty when neither option was supplied" do
        assert_empty SecretConfig::CLI.new(["--version"]).send(:kms_args)
      end

      it "passes the key id through" do
        cli = SecretConfig::CLI.new(["--key_id", "key-123"])

        assert_equal({key_id: "key-123"}, cli.send(:kms_args))
      end

      it "prefers the key alias over the key id" do
        cli = SecretConfig::CLI.new(["--key_id", "key-123", "--key_alias", "my_key"])

        assert_equal({key_alias: "my_key"}, cli.send(:kms_args))
      end
    end

    describe "#run!" do
      it "prints the version" do
        out, = capture_io { SecretConfig::CLI.new(["--version"]).run! }

        assert_equal "Secret Config v#{SecretConfig::VERSION}\n", out
      end

      it "prints the help when no operation is supplied" do
        out, = capture_io { SecretConfig::CLI.new(["--provider", "file"]).run! }

        assert_includes out, "secret-config [options]"
      end

      it "builds and runs from argv" do
        out, = capture_io { SecretConfig::CLI.run!(["--version"]) }

        assert_includes out, "Secret Config v"
      end
    end

    # The commands below are only reachable without AWS credentials now that the file provider builds.
    describe "commands against the file provider" do
      let(:path) { "/test/my_application" }

      def build_cli(argv, store)
        SecretConfig::CLI.new(argv + ["--provider", "file", "--provider-file", store])
      end

      def with_store(&)
        Dir.mktmpdir do |dir|
          store = File.join(dir, "application.yml")
          FileUtils.cp("test/config/application.yml", store)
          yield store, dir
        end
      end

      it "fetches one key" do
        with_store do |store|
          out, = capture_io { build_cli(["--fetch", "#{path}/mysql/host"], store).run! }

          assert_equal "127.0.0.1\n", out
        end
      end

      it "sets one key" do
        with_store do |store|
          capture_io { build_cli(["--set", "#{path}/mysql/host=localhost"], store).run! }

          assert_equal "localhost", SecretConfig::Providers::File.new(file_name: store).fetch("#{path}/mysql/host")
        end
      end

      it "deletes one key" do
        with_store do |store|
          capture_io { build_cli(["--delete", "#{path}/mysql/host"], store).run! }

          assert_nil SecretConfig::Providers::File.new(file_name: store).fetch("#{path}/mysql/host")
        end
      end

      it "deletes a tree" do
        with_store do |store|
          capture_io { build_cli(["--delete-tree", "#{path}/mysql"], store).run! }

          provider = SecretConfig::Providers::File.new(file_name: store)

          assert_nil provider.fetch("#{path}/mysql/host")
          assert_nil provider.fetch("#{path}/mysql/database")
          assert_equal "127.0.0.1:27017", provider.fetch("#{path}/mongo/primary")
        end
      end

      it "exports to a file, filtering secrets by default" do
        with_store do |store, dir|
          target = File.join(dir, "exported.yml")
          capture_io { build_cli(["--export", path, "--file", target], store).run! }

          config = YAML.safe_load_file(target)

          assert_equal "127.0.0.1", config.dig("mysql", "host")
          assert_equal SecretConfig::FILTERED, config.dig("mysql", "password")
        end
      end

      it "exports unfiltered with --no-filter" do
        with_store do |store, dir|
          target = File.join(dir, "exported.yml")
          capture_io { build_cli(["--export", path, "--file", target, "--no-filter"], store).run! }

          assert_equal "secret_configrules", YAML.safe_load_file(target).dig("mysql", "password")
        end
      end

      it "imports from a file into a store that does not exist yet" do
        with_store do |_store, dir|
          source = File.join(dir, "source.yml")
          File.write(source, {"mysql" => {"host" => "localhost"}}.to_yaml)
          target = File.join(dir, "new", "store.yml")

          capture_io { build_cli(["--import", path, "--file", source], target).run! }

          assert_equal "localhost", SecretConfig::Providers::File.new(file_name: target).fetch("#{path}/mysql/host")
        end
      end

      it "exports to stdout when no file is given" do
        with_store do |store|
          out, = capture_io { build_cli(["--export", path], store).run! }

          assert_equal "127.0.0.1", YAML.safe_load(out).dig("mysql", "host")
        end
      end

      it "exports json when the file name ends in .json" do
        with_store do |store, dir|
          target = File.join(dir, "exported.json")
          capture_io { build_cli(["--export", path, "--file", target], store).run! }

          assert_equal "127.0.0.1", JSON.parse(File.read(target)).dig("mysql", "host")
        end
      end

      it "copies one path onto another inside the same file" do
        with_store do |store|
          capture_io { build_cli(["--import", "/copy/my_application", "--path", path], store).run! }

          provider = SecretConfig::Providers::File.new(file_name: store)

          assert_equal "127.0.0.1", provider.fetch("/copy/my_application/mysql/host")
          assert_equal "secret_configrules", provider.fetch("/copy/my_application/mysql/password")
        end
      end

      it "diffs two paths inside the same file" do
        with_store do |store|
          capture_io { build_cli(["--import", "/copy/my_application", "--path", path], store).run! }
          capture_io { build_cli(["--set", "/copy/my_application/mysql/host=localhost"], store).run! }

          out, = capture_io { build_cli(["--diff", path, "--path", "/copy/my_application"], store).run! }

          assert_includes out, "mysql/host"
          assert_includes out, "- 127.0.0.1"
          assert_includes out, "+ localhost"
        end
      end

      it "diffs a file against the store" do
        with_store do |store, dir|
          source = File.join(dir, "source.yml")
          File.write(source, {"mysql" => {"host" => "localhost"}}.to_yaml)

          out, = capture_io { build_cli(["--diff", path, "--file", source], store).run! }

          assert_includes out, "mysql/host"
          assert_includes out, "- 127.0.0.1"
          assert_includes out, "+ localhost"
        end
      end

      it "reports a key that only the source has as an addition" do
        with_store do |store, dir|
          source = File.join(dir, "source.yml")
          File.write(source, {"mysql" => {"replica" => "127.0.0.2"}}.to_yaml)

          out, = capture_io { build_cli(["--diff", path, "--file", source], store).run! }

          assert_includes out, "mysql/replica"
          assert_includes out, "+ 127.0.0.2"
        end
      end

      it "imports from a json file" do
        with_store do |store, dir|
          source = File.join(dir, "source.json")
          File.write(source, {"mysql" => {"host" => "localhost"}}.to_json)

          capture_io { build_cli(["--import", path, "--file", source], store).run! }

          assert_equal "localhost", SecretConfig::Providers::File.new(file_name: store).fetch("#{path}/mysql/host")
        end
      end

      it "raises for a file name that is neither yml nor json" do
        with_store do |store, dir|
          error = assert_raises ArgumentError do
            capture_io { build_cli(["--export", path, "--file", File.join(dir, "exported.txt")], store).run! }
          end

          assert_includes error.message, "must end with '.yml' or '.json'"
        end
      end
    end
  end
end
