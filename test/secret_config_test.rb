require_relative 'test_helper'

class SecretConfigTest < Minitest::Test
  describe SecretConfig::Providers::File do
    let :file_name do
      File.join(File.dirname(__FILE__), 'config', 'application.yml')
    end

    let :root do
      "/development/connect"
    end

    before do
      ENV['SECRETCONFIG_FILE_NAME'] = file_name
      SecretConfig.root             = root
      SecretConfig.provider         = :file
    end

    describe '#configuration' do
      it 'returns a copy of the config' do
        assert_equal "127.0.0.1", SecretConfig.configuration["/development/connect/mysql/host"]
      end
    end

    describe '#key?' do
      it 'has key' do
        assert SecretConfig.key?("mysql/database")
      end
    end

    describe '#[]' do
      it 'returns values' do
        assert_equal "secret_config_development", SecretConfig["mysql/database"]
      end
    end

    describe '#fetch' do
      it 'fetches values' do
        assert_equal "secret_config_development", SecretConfig.fetch("mysql/database")
      end
    end
  end
end
