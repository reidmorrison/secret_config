require_relative "test_helper"

# Covers argument parsing only. The command implementations (`run_export`, `run_import`, `run_diff`, and
# friends) drive stdin/stdout and the SSM provider, and are not exercised here.
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
        assert_equal 64, SecretConfig::CLI.new(["--random_size", "64"]).random_size
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

    # Current behavior, not desired behavior: --provider advertises "[ssm | file]" but only ssm builds.
    # See TECH_DEBT.md.
    describe "#provider_instance" do
      it "raises for any provider other than ssm" do
        cli = SecretConfig::CLI.new(["--provider", "file", "--fetch", "mysql/host"])

        error = assert_raises ArgumentError do
          cli.send(:provider_instance)
        end
        assert_equal "Invalid provider: file", error.message
      end
    end
  end
end
