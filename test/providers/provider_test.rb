require_relative "../test_helper"

module Providers
  class ProviderTest < Minitest::Test
    describe SecretConfig::Providers::Provider do
      let :provider do
        SecretConfig::Providers::Provider.new
      end

      describe "abstract methods" do
        it "#each raises" do
          assert_raises(NotImplementedError) { provider.each("/test/my_application") }
        end

        it "#fetch raises" do
          assert_raises(NotImplementedError) { provider.fetch("mysql/host") }
        end

        it "#set raises" do
          assert_raises(NotImplementedError) { provider.set("mysql/host", "127.0.0.1") }
        end

        it "#delete raises" do
          assert_raises(NotImplementedError) { provider.delete("mysql/host") }
        end
      end

      describe "#to_h" do
        let :populated_provider do
          InMemoryProvider.new(
            "/test/my_application/mysql/host" => "127.0.0.1",
            "/test/my_application/mysql/port" => "3306",
            "/test/other_application/mysql/host" => "192.168.0.1"
          )
        end

        it "collects the pairs yielded by #each" do
          expected = {
            "/test/my_application/mysql/host" => "127.0.0.1",
            "/test/my_application/mysql/port" => "3306"
          }

          assert_equal expected, populated_provider.to_h("/test/my_application")
        end

        it "returns an empty hash when the path matches nothing" do
          assert_empty populated_provider.to_h("/test/missing_application")
        end
      end
    end
  end
end
