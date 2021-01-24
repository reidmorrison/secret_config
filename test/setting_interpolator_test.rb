require_relative "test_helper"
module SecretConfig
  class SettingInterpolatorTest < Minitest::Test
    describe SettingInterpolator do
      let(:interpolator) { SettingInterpolator.new }

      describe "#parse" do
        it "handles good key" do
          string   = "Set a date of ${date} here."
          expected = string.gsub("${date}", Date.today.strftime("%Y%m%d"))
          actual   = interpolator.parse(string)
          assert_equal expected, actual, string
        end

        it "handles multiple keys" do
          string   = "${pid}: Set a date of ${date} here and a ${time:%H%M} here and for luck ${pid}"
          expected = string.gsub("${date}", Date.today.strftime("%Y%m%d"))
          expected = expected.gsub("${time:%H%M}", Time.now.strftime("%H%M"))
          expected = expected.gsub("${pid}", $$.to_s)
          actual   = interpolator.parse(string)
          assert_equal expected, actual, string
        end

        it "handles bad key" do
          string = "Set a date of ${blah} here."
          assert_raises InvalidInterpolation do
            interpolator.parse(string)
          end
        end
      end

      describe "#date" do
        it "interpolates date only" do
          string   = "${date}"
          expected = Date.today.strftime("%Y%m%d")
          actual   = interpolator.parse(string)
          assert_equal expected, actual, string
        end

        it "interpolates date" do
          string   = "Set a date of ${date} here."
          expected = string.gsub("${date}", Date.today.strftime("%Y%m%d"))
          actual   = interpolator.parse(string)
          assert_equal expected, actual, string
        end

        it "interpolates date with custom format" do
          string   = "Set a custom ${date:%m%d%Y} here."
          expected = string.gsub("${date:%m%d%Y}", Date.today.strftime("%m%d%Y"))
          actual   = interpolator.parse(string)
          assert_equal expected, actual, string
        end
      end

      describe "#time" do
        it "interpolates time only" do
          string = "${time}"
          time   = Time.now
          Time.stub(:now, time) do
            expected = Time.now.strftime("%Y%m%d%H%M%S%L")
            actual   = interpolator.parse(string)
            assert_equal expected, actual, string
          end
        end

        it "interpolates time" do
          string = "Set a time of ${time} here."
          time   = Time.now
          Time.stub(:now, time) do
            expected = string.gsub("${time}", Time.now.strftime("%Y%m%d%H%M%S%L"))
            actual   = interpolator.parse(string)
            assert_equal expected, actual, string
          end
        end

        it "interpolates time with custom format" do
          string   = "Set a custom time of ${time:%H%M} here."
          expected = string.gsub("${time:%H%M}", Time.now.strftime("%H%M"))
          actual   = interpolator.parse(string)
          assert_equal expected, actual, string
        end
      end

      describe "#env" do
        before do
          ENV["TEST_SETTING"] = "Secret"
        end

        it "fetches existing ENV var" do
          string = "${env:TEST_SETTING}"
          actual = interpolator.parse(string)
          assert_equal "Secret", actual, string
        end

        it "fetches existing ENV var into a larger string" do
          string   = "Hello ${env:TEST_SETTING}. How are you?"
          actual   = interpolator.parse(string)
          expected = string.gsub("${env:TEST_SETTING}", "Secret")
          assert_equal expected, actual, string
        end

        it "handles missing ENV var" do
          string = "${env:OTHER_TEST_SETTING}"
          assert_raises SecretConfig::MissingEnvironmentVariable do
            interpolator.parse(string)
          end
        end

        it "uses default value for missing ENV var" do
          string = "${env:OTHER_TEST_SETTING,My default value}"
          actual = interpolator.parse(string)
          assert_equal "My default value", actual, string
        end
      end

      describe "#hostname" do
        it "returns hostname" do
          string = "${hostname}"
          actual = interpolator.parse(string)
          assert_equal Socket.gethostname, actual, string
        end

        it "returns short hostname" do
          string = "${hostname:short}"
          actual = interpolator.parse(string)
          assert_equal Socket.gethostname.split(".")[0], actual, string
        end
      end

      describe "#pid" do
        it "returns process id" do
          string = "${pid}"
          actual = interpolator.parse(string)
          assert_equal $$.to_s, actual, string
        end
      end

      describe "#random" do
        it "interpolates random 32 byte string" do
          string = "${random}"
          random = SecureRandom.urlsafe_base64(32)
          SecureRandom.stub(:urlsafe_base64, random) do
            actual = interpolator.parse(string)
            assert_equal random, actual, string
          end
        end

        it "interpolates custom length random string" do
          string = "${random:64}"
          random = SecureRandom.urlsafe_base64(64)
          SecureRandom.stub(:urlsafe_base64, random) do
            actual = interpolator.parse(string)
            assert_equal random, actual, string
          end
        end
      end
    end
  end
end
