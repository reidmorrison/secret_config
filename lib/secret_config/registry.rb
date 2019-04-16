require 'base64'
require 'concurrent-ruby'

module SecretConfig
  # Centralized configuration with values stored in AWS System Manager Parameter Store
  class Registry
    attr_reader :provider
    attr_accessor :root

    def initialize(root:, provider:)
      # TODO: Validate root starts with /, etc
      @root     = root
      @provider = provider
      @registry = Concurrent::Map.new
      refresh!
    end

    # Returns [Hash] a copy of the in memory configuration data.
    def configuration(relative: true, filters: SecretConfig.filters)
      h = {}
      registry.each_pair do |key, value|
        key   = relative_key(key) if relative
        value = filter_value(key, value, filters)
        decompose(key, value, h)
      end
      h
    end

    # Returns [String] configuration value for the supplied key, or nil when missing.
    def [](key)
      registry[expand_key(key)]
    end

    # Returns [String] configuration value for the supplied key, or nil when missing.
    def key?(key)
      registry.key?(expand_key(key))
    end

    # Returns [String] configuration value for the supplied key
    def fetch(key, default: nil, type: :string, encoding: nil)
      value = self[key]
      if value.nil?
        raise(MissingMandatoryKey, "Missing configuration value for #{root}/#{key}") unless default

        value = default.respond_to?(:call) ? default.call : default
      end

      value = convert_encoding(encoding, value) if encoding
      type == :string ? value : convert_type(type, value)
    end

    # Set the value for a key in the centralized configuration store.
    def set(key:, value:, encrypt: true)
      key = expand_key(key)
      provider.set(key, value, encrypt: true)
      registry[key] = value
    end

    # Refresh the in-memory cached copy of the centralized configuration information.
    # Environment variable values will take precendence over the central store values.
    def refresh!
      existing_keys = registry.keys
      updated_keys  = []
      provider.each(root) do |key, value|
        registry[key] = env_var_override(key, value)
        updated_keys << key
      end

      # Remove keys deleted from the registry.
      (existing_keys - updated_keys).each { |key| registry.delete(key) }

      true
    end

    private

    attr_reader :registry

    # Returns the value from an env var if it is present,
    # Otherwise the value is returned unchanged.
    def env_var_override(key, value)
      env_var_name = relative_key(key).upcase.gsub('/', '_')
      ENV[env_var_name] || value
    end

    # Add the root to the path if it is a relative path.
    def expand_key(key)
      key.start_with?('/') ? key : "#{root}/#{key}"
    end

    # Convert the key to a relative path by removing the
    # root path.
    def relative_key(key)
      key.start_with?('/') ? key.sub("#{root}/", '') : key
    end

    def filter_value(key, value, filters)
      return value unless filters

      _, name = File.split(key)
      filter = filters.any? do |filter|
        filter.is_a?(Regexp) ? name =~ filter : name == filter
      end

      filter ? '[FILTERED]' : value
    end

    def decompose(key, value, h = {})
      path, name = File.split(key)
      last       = path.split('/').reduce(h) do |target, path|
        if path == ''
          target
        elsif target.key?(path)
          target[path]
        else
          target[path] = {}
        end
      end
      last[name] = value
      h
    end

    def convert_encoding(encoding, value)
      case encoding
      when :base64
        Base64.decode64(value)
      else
        value
      end
    end

    def convert_type(type, value)
      case type
      when :integer
        value.to_i
      when :float
        value.to_f
      when :string
        value
      when :boolean
        %w[true 1 t].include?(value.to_s.downcase)
      when :symbol
        value.to_sym unless value.nil? || value.to_s.strip == ''
      end
    end

  end
end
