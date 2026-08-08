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

    describe "#set_config" do
      let(:path) { "/test/my_application" }
      let(:provider) { InMemoryProvider.new }

      # `provider_instance` memoizes, and only builds :ssm, so inject a writable provider instead.
      # Parsing is wrapped because --random_size emits a deprecation warning on stderr.
      def build_cli(argv)
        cli = nil
        capture_io { cli = SecretConfig::CLI.new(argv) }
        cli.tap { |instance| instance.instance_variable_set(:@provider_instance, provider) }
      end

      def set_config(cli, config, current_values, force: false)
        capture_io { cli.send(:set_config, config, path, current_values, force: force) }
      end

      it "skips unchanged values" do
        cli = build_cli(["--import", path])
        set_config(cli, {"mysql" => {"host" => "localhost"}}, {"#{path}/mysql/host" => "localhost"})

        assert_empty provider.hash
      end

      it "writes unchanged values when forced, so they are re-encrypted under a new KMS key" do
        cli = build_cli(["--import", path, "--force"])
        set_config(cli, {"mysql" => {"host" => "localhost"}}, {"#{path}/mysql/host" => "localhost"}, force: true)

        assert_equal({"#{path}/mysql/host" => "localhost"}, provider.hash)
      end

      it "generates a value for __generate__ when the key is absent" do
        cli = build_cli(["--import", path])
        set_config(cli, {"mysql" => {"password" => SecretConfig::GENERATE}}, {})

        generated = provider.hash["#{path}/mysql/password"]

        refute_equal SecretConfig::GENERATE, generated
        refute_nil generated
      end

      it "leaves an existing __generate__ value alone" do
        cli = build_cli(["--import", path])
        set_config(cli, {"mysql" => {"password" => SecretConfig::GENERATE}},
                   {"#{path}/mysql/password" => "existing"})

        assert_empty provider.hash
      end

      # --force must not regenerate persisted secrets. It exists so that unchanged keys are re-written and
      # therefore re-encrypted under a new KMS key; regenerating during that would silently invalidate
      # every generated value in the source.
      it "leaves an existing __generate__ value alone when forced" do
        cli = build_cli(["--import", path, "--force"])
        set_config(cli, {"mysql" => {"password" => SecretConfig::GENERATE}},
                   {"#{path}/mysql/password" => "existing"}, force: true)

        assert_empty provider.hash
      end

      it "ignores surrounding whitespace around __generate__" do
        cli = build_cli(["--import", path])
        set_config(cli, {"mysql" => {"password" => "  #{SecretConfig::GENERATE}  "}}, {})

        refute_nil provider.hash["#{path}/mysql/password"]
      end

      it "generates --random_size bytes by default" do
        cli = build_cli(["--import", path, "--random_size", "48"])
        SecureRandom.stub(:urlsafe_base64, ->(size) { "generated-#{size}" }) do
          set_config(cli, {"mysql" => {"password" => SecretConfig::GENERATE}}, {})
        end

        assert_equal "generated-48", provider.hash["#{path}/mysql/password"]
      end

      it "generates the size supplied by __generate__:size in preference to --random_size" do
        cli = build_cli(["--import", path, "--random_size", "48"])
        SecureRandom.stub(:urlsafe_base64, ->(size) { "generated-#{size}" }) do
          set_config(cli, {"mysql" => {"password" => "#{SecretConfig::GENERATE}:64"}}, {})
        end

        assert_equal "generated-64", provider.hash["#{path}/mysql/password"]
      end

      it "raises for a malformed generate token rather than importing it literally" do
        cli = build_cli(["--import", path])

        error = assert_raises ArgumentError do
          set_config(cli, {"mysql" => {"password" => "__generate__:abc"}}, {})
        end

        assert_includes error.message, "Invalid generate token"
        assert_includes error.message, "mysql/password"
        assert_empty provider.hash
      end

      it "raises for a zero size, rather than storing an empty secret" do
        cli = build_cli(["--import", path])

        assert_raises ArgumentError do
          set_config(cli, {"mysql" => {"password" => "#{SecretConfig::GENERATE}:0"}}, {})
        end
        assert_empty provider.hash
      end

      describe "the deprecated $(random) spelling" do
        before do
          # The warning is emitted once per distinct message per process, so reset it between tests.
          SecretConfig.instance_variable_set(:@deprecation_warnings, Set.new)
        end

        it "still generates a value" do
          cli = build_cli(["--import", path])
          set_config(cli, {"mysql" => {"password" => SecretConfig::RANDOM}}, {})

          refute_nil provider.hash["#{path}/mysql/password"]
        end

        it "warns on stderr, naming the key and the replacement" do
          cli = build_cli(["--import", path])
          _, err = capture_io do
            cli.send(:set_config, {"mysql" => {"password" => SecretConfig::RANDOM}}, path, {})
          end

          assert_includes err, "Deprecation"
          assert_includes err, SecretConfig::GENERATE
          assert_includes err, "#{path}/mysql/password"
        end

        it "warns only once for repeated use of the same key" do
          cli = build_cli(["--import", path])
          _, err = capture_io do
            2.times { cli.send(:set_config, {"mysql" => {"password" => SecretConfig::RANDOM}}, path, {}) }
          end

          assert_equal 1, err.scan("Deprecation").size
        end
      end

      it "reports a forced key as changed rather than added" do
        cli = build_cli(["--import", path, "--force"])
        out, = capture_io do
          cli.send(:set_config, {"mysql" => {"host" => "localhost"}}, path,
                   {"#{path}/mysql/host" => "localhost"}, force: true)
        end

        assert_includes out, "* #{path}/mysql/host"
        refute_includes out, "+ #{path}/mysql/host"
      end
    end
  end
end
