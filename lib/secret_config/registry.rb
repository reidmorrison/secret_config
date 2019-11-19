require "base64"
require "concurrent-ruby"

module SecretConfig
  # Centralized configuration with values stored in AWS System Manager Parameter Store
  class Registry
    attr_reader :provider
    attr_accessor :path

    def initialize(path: nil, provider: nil, provider_args: nil)
      @path = default_path(path)
      raise(UndefinedRootError, "Root must start with /") unless @path.start_with?("/")

      resolved_provider = default_provider(provider)
      provider_args     = nil if resolved_provider != provider

      @provider = create_provider(resolved_provider, provider_args)
      @cache    = Concurrent::Map.new
      refresh!
    end

    # Returns [Hash] a copy of the in memory configuration data.
    def configuration(relative: true, filters: SecretConfig.filters)
      h = {}
      cache.each_pair do |key, value|
        key   = relative_key(key) if relative
        value = filter_value(key, value, filters)
        Utils.decompose(key, value, h)
      end
      h
    end

    # Returns [String] configuration value for the supplied key, or nil when missing.
    def [](key)
      cache[expand_key(key)]
    end

    # Returns [String] configuration value for the supplied key, or nil when missing.
    def key?(key)
      cache.key?(expand_key(key))
    end

    # Returns [String] configuration value for the supplied key
    def fetch(key, default: :no_default_supplied, type: :string, encoding: nil)
      value = self[key]
      if value.nil?
        raise(MissingMandatoryKey, "Missing configuration value for #{path}/#{key}") if default == :no_default_supplied

        value = default.respond_to?(:call) ? default.call : default
      end

      value = convert_encoding(encoding, value) if encoding
      type == :string ? value : convert_type(type, value)
    end

    # Set the value for a key in the centralized configuration store.
    def []=(key, value)
      set(key, value)
    end

    # Set the value for a key in the centralized configuration store.
    def set(key, value)
      key = expand_key(key)
      provider.set(key, value)
      cache[key] = value
    end

    # Delete a key from the centralized configuration store.
    def delete(key)
      key = expand_key(key)
      provider.delete(key)
      cache.delete(key)
    end

    # Refresh the in-memory cached copy of the centralized configuration information.
    # Environment variable values will take precendence over the central store values.
    def refresh!
      existing_keys = cache.keys
      updated_keys  = []
      provider.each(path) do |key, value|
        cache[key] = env_var_override(key, value)
        updated_keys << key
      end

      # Remove keys deleted from the central registry.
      (existing_keys - updated_keys).each { |key| provider.delete(key) }

      true
    end

    private

    attr_reader :cache

    # Returns the value from an env var if it is present,
    # Otherwise the value is returned unchanged.
    def env_var_override(key, value)
      env_var_name = relative_key(key).upcase.gsub("/", "_")
      ENV[env_var_name] || value
    end

    # Add the path to the path if it is a relative path.
    def expand_key(key)
      key.start_with?("/") ? key : "#{path}/#{key}"
    end

    # Convert the key to a relative path by removing the path.
    def relative_key(key)
      key.start_with?("/") ? key.sub("#{path}/", "") : key
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
      when :integer
        value.to_i
      when :float
        value.to_f
      when :string
        value
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

      path.start_with?("/") ? path : "/#{path}"
    end

    def default_provider(provider)
      provider = (ENV["SECRET_CONFIG_PROVIDER"] || provider || "file")

      return provider if provider.respond_to?(:each) && provider.respond_to?(:set)

      provider.to_s.downcase.to_sym
    end
  end
end
