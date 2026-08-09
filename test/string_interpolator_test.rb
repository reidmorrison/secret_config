require_relative "test_helper"

class StringInterpolatorTest < Minitest::Test
  describe SecretConfig::StringInterpolator do
    # StringInterpolator has no interpolations of its own, so use the subclass that supplies them.
    let :interpolator do
      SecretConfig::SettingInterpolator.new
    end

    describe "#parse" do
      it "leaves a string without any tokens alone" do
        assert_equal "no tokens here", interpolator.parse("no tokens here")
      end

      it "does not interpolate an escaped token" do
        assert_equal "${date}", interpolator.parse("$${date}")
      end

      it "keeps the surrounding text when unescaping" do
        assert_equal "literal ${pid} value", interpolator.parse("literal $${pid} value")
      end

      it "does not require the escaped key to be a valid interpolation" do
        assert_equal "${not_a_key}", interpolator.parse("$${not_a_key}")
      end

      it "leaves a lone $$ untouched" do
        assert_equal "$$", interpolator.parse("$$")
      end

      it "raises for an unknown key" do
        assert_raises SecretConfig::InvalidInterpolation do
          interpolator.parse("${not_a_key}")
        end
      end

      it "raises rather than passing the wrong number of arguments to an interpolation" do
        error = assert_raises SecretConfig::InvalidInterpolation do
          interpolator.parse("${pid:extra}")
        end

        assert_includes error.message, "Invalid arguments for key: pid"
      end
    end

    # Dispatch was guarded by `respond_to?`, which is true for every method an object inherits. A
    # value in the central store could name `Object#send`, and through it reach any private method,
    # so anything able to write one setting could run code in every process that loaded that path.
    describe "dispatch" do
      it "refuses to call an inherited method" do
        %w[
          ${send:eval,exit}
          ${public_send:system,id}
          ${instance_eval:exit}
          ${instance_variable_get:@pattern}
          ${method:parse}
          ${display}
          ${freeze}
          ${itself}
          ${class}
        ].each do |token|
          assert_raises SecretConfig::InvalidInterpolation, "expected #{token} to be refused" do
            interpolator.parse(token)
          end
        end
      end

      it "refuses to call parse itself" do
        assert_raises SecretConfig::InvalidInterpolation do
          interpolator.parse("${parse:anything}")
        end
      end

      it "dispatches every declared interpolation and nothing else" do
        assert_equal %i[date time env hostname pid random select].sort,
                     SecretConfig::SettingInterpolator.interpolations.sort
      end
    end

    describe ".interpolation" do
      let :subclass do
        Class.new(SecretConfig::SettingInterpolator) do
          interpolation :colour

          def colour(name = "red")
            name
          end

          def undeclared
            "reachable"
          end
        end
      end

      it "adds a token to the subclass" do
        assert_equal "red", subclass.new.parse("${colour}")
        assert_equal "blue", subclass.new.parse("${colour:blue}")
      end

      it "keeps the interpolations of the superclass" do
        assert_equal $$.to_s, subclass.new.parse("${pid}")
      end

      it "leaves a public method that was not declared unreachable" do
        assert_raises SecretConfig::InvalidInterpolation do
          subclass.new.parse("${undeclared}")
        end
      end

      it "does not add the token to the superclass" do
        refute_includes SecretConfig::SettingInterpolator.interpolations, :colour
      end
    end
  end
end
