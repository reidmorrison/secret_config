require 'base64'

module SecretConfig
  # Centralized configuration with values stored in AWS System Manager Parameter Store
  #
  # Values are fetched from the central store on startup. Only those values starting with the specified
  # root are loaded, supply multiple paths using the env var SECRETCONFIG_PATHS.
  #
  # Existing event mechanisms can be used to force a reload of the cached copy.
  class Registry
    attr_reader :provider
    attr_accessor :root

    def initialize(root:, provider: :ssm)
      # TODO: Validate root starts with /, etc
      @root     = root
      @provider = provider
      refresh!
    end

    # Returns [Hash] a copy of the in memory configuration data.
    def configuration
      h = {}
      registry.each_pair { |key, value| h[key] = value }
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

    def set(key:, value:, encrypt: true)
      SSM.new(key_id: key_id).set(expand_key(key), value, encrypt: encrypt)
    end

    def refresh!
      h = {}
      implementation.each(root) { |k, v| h[k] = v }
      @registry = h
    end

    private

    attr_reader :registry

    def expand_key(key)
      key.start_with?('/') ? key : "#{root}/#{key}"
    end

    def implementation
      @implementation ||= constantize_symbol(provider).new
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
      end
    end

    def constantize_symbol(symbol, namespace = 'SecretConfig::Providers')
      klass = "#{namespace}::#{camelize(symbol.to_s)}"
      begin
        Object.const_get(klass)
      rescue NameError
        raise(ArgumentError, "Could not convert symbol: #{symbol.inspect} to a class in: #{namespace}. Looking for: #{klass}")
      end
    end

    # Borrow from Rails, when not running Rails
    def camelize(term)
      string = term.to_s
      string = string.sub(/^[a-z\d]*/, &:capitalize)
      string.gsub!(/(?:_|(\/))([a-z\d]*)/i) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).capitalize}" }
      string.gsub!('/'.freeze, '::'.freeze)
      string
    end

  end
end
