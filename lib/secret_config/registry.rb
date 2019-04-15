require 'base64'

module SecretConfig
  # Centralized configuration with values stored in AWS System Manager Parameter Store
  class Registry
    attr_reader :provider
    attr_accessor :root

    def initialize(root:, provider:)
      # TODO: Validate root starts with /, etc
      @root     = root
      @provider = provider
      refresh!
    end

    # Returns [Hash] a copy of the in memory configuration data.
    def configuration
      h = {}
      registry.each_pair { |k, v| decompose(k, v, h) }
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
      provider.each(root) { |k, v| h[k] = v }
      @registry = h
    end

    private

    attr_reader :registry

    def expand_key(key)
      key.start_with?('/') ? key : "#{root}/#{key}"
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
