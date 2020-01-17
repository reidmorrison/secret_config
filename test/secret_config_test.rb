require_relative 'test_helper'
require 'socket'

class SecretConfigTest < Minitest::Test
  describe SecretConfig::Providers::File do
    let :file_name do
      File.join(File.dirname(__FILE__), 'config', 'application.yml')
    end

    let :path do
      "/test/my_application"
    end

    before do
      SecretConfig.use :file, path: path, file_name: file_name
    end

    describe '#configuration' do
      it 'returns a copy of the config' do
        assert_equal "127.0.0.1", SecretConfig.configuration.dig("mysql", "host")
      end
    end

    describe '#key?' do
      it 'has key' do
        assert SecretConfig.key?("mysql/database")
      end
    end

    describe '#[]' do
      it 'returns values' do
        assert_equal "secret_config_test", SecretConfig["mysql/database"]
      end

      it 'returns values with interpolation' do
        assert_equal "#{Socket.gethostname}:27018", SecretConfig["mongo/secondary"]
      end
    end

    describe '#fetch' do
      after do
        ENV['MYSQL_DATABASE'] = nil
      end

      it 'fetches values' do
        assert_equal "secret_config_test", SecretConfig.fetch("mysql/database")
      end

      it 'can be overridden by an environment variable' do
        ENV['MYSQL_DATABASE'] = 'other'

        SecretConfig.use :file, path: path, file_name: file_name
        assert_equal "other", SecretConfig.fetch("mysql/database")
      end

      it 'returns values with interpolation' do
        assert_equal "#{Socket.gethostname}:27018", SecretConfig.fetch("mongo/secondary")
      end
    end
  end
end
