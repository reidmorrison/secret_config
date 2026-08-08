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
      value = env_var_value(key) if value.nil?
      value&.to_s
    end

    # Returns [true|false] whether a value is available for the supplied key.
    #
    # A key that is present only as an environment variable is included when
    # `SecretConfig.check_env_var?` is true, so that `key?` agrees with `[]` and `fetch`.
    def key?(key)
      return true if cache.key?(key)

      !env_var_value(key).nil?
    end

    # Returns [String] configuration value for the supplied key
    # Convert the string value into an array of values by supplying a `separator`.
    #
    # When the key is missing the block is called, if supplied, otherwise `default` is used.
    # Without either, `MissingMandatoryKey` is raised.
    def fetch(key, default: :no_default_supplied, type: :string, encoding: nil, separator: nil)
      value = self[key]
      if value.nil?
        if block_given?
          value = yield
        elsif default == :no_default_supplied
          raise(MissingMandatoryKey, "Missing configuration value for #{path}/#{key}")
        else
          value = default
        end
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
    #
    # Returns true. The name cannot change to satisfy Naming/PredicateMethod, since `refresh!` is
    # public API and is delegated from `SecretConfig.refresh!`.
    def refresh! # rubocop:disable Naming/PredicateMethod
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
    #
    # `fetch_chain` holds the absolute paths already being fetched further up, since every absolute
    # `__import__` is resolved by a new `Parser` that cannot see the one that asked for it.
    def fetch_path(path, fetch_chain = [])
      parser = Parser.new(path, self, interpolate: interpolate, fetch_chain: fetch_chain + [path])
      provider.each(path) { |key, value| parser.parse(key, value) }
      parser.render
    end

    # Returns the value from an env var if it is present,
    # Otherwise the value is returned unchanged.
    def env_var_override(key, value)
      env_var_value(key) || value
    end

    # Returns [String] the environment variable override for the supplied key,
    # or nil when there is none, or when env var checking is disabled.
    def env_var_value(key)
      return nil unless SecretConfig.check_env_var?

      ENV.fetch(key.upcase.gsub("/", "_"), nil)
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
        value&.to_s
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
      path = ENV["SECRET_CONFIG_PATH"] || configured_path || ENV.fetch("RAILS_ENV", nil)
      path = Rails.env if path.nil? && defined?(Rails) && Rails.respond_to?(:env)

      raise(UndefinedRootError, "Either set env var 'SECRET_CONFIG_PATH' or call SecretConfig.use") unless path

      relative_key?(path) ? "/#{path}" : path
    end

    def default_provider(provider)
      provider = ENV["SECRET_CONFIG_PROVIDER"] || provider || "file"

      return provider if provider.respond_to?(:each) && provider.respond_to?(:set)

      provider.to_s.downcase.to_sym
    end
  end
end
