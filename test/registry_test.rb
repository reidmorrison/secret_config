require_relative 'test_helper'

class RegistryTest < Minitest::Test
  describe SecretConfig::Providers::File do
    let :file_name do
      File.join(File.dirname(__FILE__), 'config', 'application.yml')
    end

    let :root do
      "/development/connect"
    end

    let :registry do
      ENV['SECRETCONFIG_FILE_NAME'] = file_name

      SecretConfig::Registry.new(root: root, provider: :file)
    end

    let :expected do
      {
        "/development/connect/mongo/database"               => "secret_config_development",
        "/development/connect/mongo/primary"                => "127.0.0.1:27017",
        "/development/connect/mongo/secondary"              => "127.0.0.1:27018",
        "/development/connect/mysql/database"               => "secret_config_development",
        "/development/connect/mysql/password"               => "secret_configrules",
        "/development/connect/mysql/username"               => "secret_config",
        "/development/connect/mysql/host"                   => "127.0.0.1",
        "/development/connect/secrets/secret_key_base"      => "somereallylongstring",
        "/development/connect/symmetric_encryption/key"     => "QUJDREVGMTIzNDU2Nzg5MEFCQ0RFRjEyMzQ1Njc4OTA=",
        "/development/connect/symmetric_encryption/version" => 2,
        "/development/connect/symmetric_encryption/iv"      => "QUJDREVGMTIzNDU2Nzg5MA=="
      }
    end

    describe '#configuration' do
      it 'returns a copy of the config' do
        paths = registry.configuration

        expected.each_pair do |key, value|
          assert_equal value, paths[key], "Path: #{key}"
        end
      end
    end

    describe '#key?' do
      it 'has key' do
        expected.each_pair do |key, value|
          key = key.sub("#{root}/", "")
          assert registry.key?(key), "Path: #{key}"
        end
      end

      it 'returns false with missing relative key' do
        refute registry.key?("invalid/path")
      end

      it 'returns nil with missing full key' do
        refute registry.key?("/development/invalid/path")
      end
    end

    describe '#[]' do
      it 'returns values' do
        expected.each_pair do |key, value|
          key = key.sub("#{root}/", "")
          assert_equal value, registry[key], "Path: #{key}"
        end
      end

      it 'returns nil with missing relative key' do
        assert_nil registry["invalid/path"]
      end

      it 'returns nil with missing full key' do
        assert_nil registry["/development/invalid/path"]
      end
    end

    describe '#fetch' do
      it 'returns values' do
        expected.each_pair do |key, value|
          key = key.sub("#{root}/", "")
          assert_equal value, registry.fetch(key), "Path: #{key}"
        end
      end

      it 'exception missing relative key' do
        assert_raises SecretConfig::MissingMandatoryKey do
          registry.fetch("invalid/path")
        end
      end

      it 'returns nil with missing full key' do
        assert_raises SecretConfig::MissingMandatoryKey do
          registry.fetch("/development/invalid/path")
        end
      end

      it 'returns default with missing key' do
        assert_equal "default_value", registry.fetch("/development/invalid/path", default: "default_value")
      end

      it 'converts to integer' do
        assert_equal 2, registry.fetch("symmetric_encryption/version", type: :integer)
      end

      it 'decodes Base 64' do
        assert_equal "ABCDEF1234567890ABCDEF1234567890", registry.fetch("symmetric_encryption/key", encoding: :base64)
      end
    end
  end
end
