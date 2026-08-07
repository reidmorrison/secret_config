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
    end
  end
end
