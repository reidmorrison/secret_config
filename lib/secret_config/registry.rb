require "base64"
require "concurrent-ruby"

module SecretConfig
  # Centralized configuration with values stored in AWS System Manager Parameter Store
  class Registry
    attr_reader :provider, :interpolate
    attr_accessor :path

    def initialize(path: nil, provider: nil, provider_args: nil, interpolate: true)
      @path = default_path(path)
      raise(UndefinedRootError, "Root must start with /") unless @path.start_with?("/")

      resolved_provider = default_provider(provider)
      provider_args     = nil if resolved_provider != provider

      @provider    = create_provider(resolved_provider, provider_args)
      @cache       = Concurrent::Map.new
      @interpolate = interpolate
      refresh!
    end

    # Returns [Hash] a copy of the in memory configuration data.
    #
    # Supply the relative path to start from so that only keys and values in that
    # path will be returned.
    def configuration(path: nil, filters: SecretConfig.filters)
      h = {}
      cache.each_pair do |key, value|
        next if path && !key.start_with?(path)

        value = filter_value(key, value, filters)
        Utils.decompose(key, value, h)
      end
      h
    end

    # Returns [String] configuration value for the supplied key, or nil when missing.
    def [](key)
      value = cache[key]
      if value.nil? && SecretConfig.check_env_var?
        value      = env_var_override(key, value)
        cache[key] = value unless value.nil?
      end
      value.nil? ? nil : value.to_s
    end

    # Returns [String] configuration value for the supplied key, or nil when missing.
    def key?(key)
      cache.key?(key)
    end

    # Returns [String] configuration value for the supplied key
    # Convert the string value into an array of values by supplying a `separator`.
    def fetch(key, default: :no_default_supplied, type: :string, encoding: nil, separator: nil)
      value = self[key]
      if value.nil?
        raise(MissingMandatoryKey, "Missing configuration value for #{path}/#{key}") if default == :no_default_supplied

        value = block_given? ? yield : default
      end

      value = convert_encoding(encoding, value) if encoding

      return convert_type(type, value) unless separator
      return value if value.is_a?(Array)

      value.to_s.split(separator).collect { |element| convert_type(type, element.strip) }
    end

    # Set the value for a key in the centralized configuration store.
    def []=(key, value)
      set(key, value)
    end

    # Set the value for a key in the centralized configuration store.
    def set(key, value)
      full_key = expand_key(key)
      provider.set(full_key, value)
      cache[key] = value
    end

    # Delete a key from the centralized configuration store.
    def delete(key)
      full_key = expand_key(key)
      provider.delete(full_key)
      cache.delete(key)
    end

    # Refresh the in-memory cached copy of the centralized configuration information.
    # Environment variable values will take precedence over the central store values.
    def refresh!
      existing_keys = cache.keys
      updated_keys  = []
      fetch_path(path).each_pair do |key, value|
        cache[key] = env_var_override(key, value)
        updated_keys << key
      end

      # Remove keys deleted from the central registry.
      (existing_keys - updated_keys).each { |key| cache.delete(key) }

      true
    end

    private

    attr_reader :cache

    # Returns [true|false] whether the supplied key is considered a relative key.
    def relative_key?(key)
      !key.start_with?("/")
    end

    # Returns a flat path of keys and values from the provider without looking in the local path.
    # Keys are returned with path names relative to the supplied path.
    def fetch_path(path)
      parser = Parser.new(path, self, interpolate: interpolate)
      provider.each(path) { |key, value| parser.parse(key, value) }
      parser.render
    end

    # Returns the value from an env var if it is present,
    # Otherwise the value is returned unchanged.
    def env_var_override(key, value)
      return value unless SecretConfig.check_env_var?

      env_var_name = key.upcase.gsub("/", "_")
      ENV[env_var_name] || value
    end

    # Add the path to the path if it is a relative path.
    def expand_key(key)
      relative_key?(key) ? "#{path}/#{key}" : key
    end

    def filter_value(key, value, filters)
      return value unless filters

      _, name  = File.split(key)
      filtered = filters.any? { |filter| filter.is_a?(Regexp) ? name =~ filter : name == filter }
      filtered ? FILTERED : value
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
      when :string
        value.nil? ? nil : value.to_s
      when :integer
        value.to_i
      when :float
        value.to_f
      when :boolean
        %w[true 1 t].include?(value.to_s.downcase)
      when :symbol
        value.to_sym unless value.nil? || value.to_s.strip == ""
      when :json
        value.nil? ? nil : JSON.parse(value)
      else
        raise(ArgumentError, "Unrecognized type:#{type}")
      end
    end

    # Create a new provider instance unless it is alread a provider instance.
    def create_provider(provider, args = nil)
      return provider if provider.respond_to?(:each) && provider.respond_to?(:set)

      klass = Utils.constantize_symbol(provider)
      args && !args.empty? ? klass.new(**args) : klass.new
    end

    def default_path(configured_path)
      path = ENV["SECRET_CONFIG_PATH"] || configured_path || ENV["RAILS_ENV"]
      path = Rails.env if path.nil? && defined?(Rails) && Rails.respond_to?(:env)

      raise(UndefinedRootError, "Either set env var 'SECRET_CONFIG_PATH' or call SecretConfig.use") unless path

      relative_key?(path) ? "/#{path}" : path
    end

    def default_provider(provider)
      provider = (ENV["SECRET_CONFIG_PROVIDER"] || provider || "file")

      return provider if provider.respond_to?(:each) && provider.respond_to?(:set)

      provider.to_s.downcase.to_sym
    end
  end
end
