require "yaml"
require "erb"

module SecretConfig
  module Providers
    # Read configuration from a local file
    class File < Provider
      attr_reader :file_name

      def initialize(file_name: "config/application.yml")
        @file_name = file_name
        raise(ConfigurationError, "Cannot find config file: #{file_name}") unless ::File.exist?(file_name)
      end

      # Yields the key with its absolute path and corresponding string value
      def each(path, &block)
        settings = fetch_path(path)

        raise(ConfigurationError, "Path #{paths.join('/')} not found in file: #{file_name}") unless settings

        Utils.flatten_each(settings, path, &block)
        nil
      end

      # Returns the value or `nil` if not found
      def fetch(_key)
        values = fetch_path(path)
        values.is_a?(Hash) ? nil : values
      end

      private

      def fetch_path(path)
        config = load_yaml(ERB.new(::File.new(file_name).read).result)

        paths = path.sub(%r{\A/*}, "").sub(%r{/*\Z}, "").split("/")
        config.dig(*paths)
      end

      def load_yaml(src)
        return YAML.safe_load(src, permitted_classes: [Symbol], aliases: true) if Psych::VERSION > "4.0"

        YAML.load(src)
      end
    end
  end
end
