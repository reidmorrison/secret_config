require_relative "../test_helper"

# Covers the write half of `--import`: which keys are written, which are skipped, and how the
# `__generate__` token is resolved. Driven directly rather than through `CLI`, since the only thing
# it needs from the CLI is a provider to write through.
class ImporterTest < Minitest::Test
  describe SecretConfig::CLI::Importer do
    let(:path) { "/test/my_application" }
    let(:provider) { InMemoryProvider.new }

    def build_importer(random_size: 32)
      SecretConfig::CLI::Importer.new(provider: provider, random_size: random_size)
    end

    describe "#set_config" do
      def set_config(importer, config, current_values, force: false)
        capture_io { importer.set_config(config, path, current_values, force: force) }
      end

      it "skips unchanged values" do
        set_config(build_importer, {"mysql" => {"host" => "localhost"}}, {"#{path}/mysql/host" => "localhost"})

        assert_empty provider.hash
      end

      it "writes unchanged values when forced, so they are re-encrypted under a new KMS key" do
        set_config(build_importer, {"mysql" => {"host" => "localhost"}},
                   {"#{path}/mysql/host" => "localhost"}, force: true)

        assert_equal({"#{path}/mysql/host" => "localhost"}, provider.hash)
      end

      # An export filters secrets by default, so a [FILTERED] value in the source means the secret was
      # never in the file. Writing it would replace the real value with the placeholder.
      it "skips filtered values" do
        set_config(build_importer, {"mysql" => {"password" => SecretConfig::FILTERED}}, {})

        assert_empty provider.hash
      end

      it "generates a value for __generate__ when the key is absent" do
        set_config(build_importer, {"mysql" => {"password" => SecretConfig::GENERATE}}, {})

        generated = provider.hash["#{path}/mysql/password"]

        refute_equal SecretConfig::GENERATE, generated
        refute_nil generated
      end

      it "leaves an existing __generate__ value alone" do
        set_config(build_importer, {"mysql" => {"password" => SecretConfig::GENERATE}},
                   {"#{path}/mysql/password" => "existing"})

        assert_empty provider.hash
      end

      # --force must not regenerate persisted secrets. It exists so that unchanged keys are re-written and
      # therefore re-encrypted under a new KMS key; regenerating during that would silently invalidate
      # every generated value in the source.
      it "leaves an existing __generate__ value alone when forced" do
        set_config(build_importer, {"mysql" => {"password" => SecretConfig::GENERATE}},
                   {"#{path}/mysql/password" => "existing"}, force: true)

        assert_empty provider.hash
      end

      it "ignores surrounding whitespace around __generate__" do
        set_config(build_importer, {"mysql" => {"password" => "  #{SecretConfig::GENERATE}  "}}, {})

        refute_nil provider.hash["#{path}/mysql/password"]
      end

      it "generates --random_size bytes by default" do
        importer = build_importer(random_size: 48)
        SecureRandom.stub(:urlsafe_base64, ->(size) { "generated-#{size}" }) do
          set_config(importer, {"mysql" => {"password" => SecretConfig::GENERATE}}, {})
        end

        assert_equal "generated-48", provider.hash["#{path}/mysql/password"]
      end

      it "generates the size supplied by __generate__:size in preference to --random_size" do
        importer = build_importer(random_size: 48)
        SecureRandom.stub(:urlsafe_base64, ->(size) { "generated-#{size}" }) do
          set_config(importer, {"mysql" => {"password" => "#{SecretConfig::GENERATE}:64"}}, {})
        end

        assert_equal "generated-64", provider.hash["#{path}/mysql/password"]
      end

      it "raises for a malformed generate token rather than importing it literally" do
        error = assert_raises ArgumentError do
          set_config(build_importer, {"mysql" => {"password" => "__generate__:abc"}}, {})
        end

        assert_includes error.message, "Invalid generate token"
        assert_includes error.message, "mysql/password"
        assert_empty provider.hash
      end

      it "raises for a zero size, rather than storing an empty secret" do
        assert_raises ArgumentError do
          set_config(build_importer, {"mysql" => {"password" => "#{SecretConfig::GENERATE}:0"}}, {})
        end
        assert_empty provider.hash
      end

      it "reports a forced key as changed rather than added" do
        out, = capture_io do
          build_importer.set_config({"mysql" => {"host" => "localhost"}}, path,
                                    {"#{path}/mysql/host" => "localhost"}, force: true)
        end

        assert_includes out, "* #{path}/mysql/host"
        refute_includes out, "+ #{path}/mysql/host"
      end

      describe "the deprecated $(random) spelling" do
        before do
          # The warning is emitted once per distinct message per process, so reset it between tests.
          SecretConfig.instance_variable_set(:@warnings, Set.new)
        end

        it "still generates a value" do
          set_config(build_importer, {"mysql" => {"password" => SecretConfig::RANDOM}}, {})

          refute_nil provider.hash["#{path}/mysql/password"]
        end

        it "warns on stderr, naming the key and the replacement" do
          _, err = capture_io do
            build_importer.set_config({"mysql" => {"password" => SecretConfig::RANDOM}}, path, {})
          end

          assert_includes err, "Deprecation"
          assert_includes err, SecretConfig::GENERATE
          assert_includes err, "#{path}/mysql/password"
        end

        it "warns only once for repeated use of the same key" do
          importer = build_importer
          _, err   = capture_io do
            2.times { importer.set_config({"mysql" => {"password" => SecretConfig::RANDOM}}, path, {}) }
          end

          assert_equal 1, err.scan("Deprecation").size
        end
      end
    end

    describe "#import" do
      it "writes every key in the config" do
        capture_io { build_importer.import({"mysql" => {"host" => "localhost"}}, path) }

        assert_equal({"#{path}/mysql/host" => "localhost"}, provider.hash)
      end

      it "leaves keys that are absent from the config alone unless pruning" do
        provider.set("#{path}/mysql/database", "test")
        capture_io do
          build_importer.import({"mysql" => {"host" => "localhost"}}, path,
                                {"#{path}/mysql/database" => "test"})
        end

        assert_equal "test", provider.hash["#{path}/mysql/database"]
      end

      # The delete pauses for 5 seconds first, to give the operator a chance to interrupt it.
      it "deletes keys that are absent from the config when pruning" do
        provider.set("#{path}/mysql/database", "test")
        importer = build_importer
        out,     = capture_io do
          importer.stub(:sleep, nil) do
            importer.import({"mysql" => {"host" => "localhost"}}, path,
                            {"#{path}/mysql/database" => "test"}, prune: true)
          end
        end

        assert_includes out, "Going to delete the following keys:"
        refute_includes provider.hash, "#{path}/mysql/database"
        assert_equal "localhost", provider.hash["#{path}/mysql/host"]
      end
    end
  end
end
