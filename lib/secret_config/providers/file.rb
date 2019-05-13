require 'yaml'
require 'erb'

module SecretConfig
  module Providers
    # Read configuration from a local file
    class File < Provider
      attr_reader :file_name

      def initialize(file_name: "config/application.yml")
        @file_name = file_name
        raise(ConfigurationError, "Cannot find config file: #{file_name}") unless ::File.exist?(file_name)
      end

      def each(path, &block)
        config = YAML.load(ERB.new(::File.new(file_name).read).result)

        paths    = path.sub(/\A\/*/, '').sub(/\/*\Z/, '').split("/")
        settings = config.dig(*paths)

        raise(ConfigurationError, "Path #{paths.join("/")} not found in file: #{file_name}") unless settings

        Utils.flatten_each(settings, path, &block)
        nil
      end
    end
  end
end
