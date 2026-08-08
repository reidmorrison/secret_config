require "securerandom"

module SecretConfig
  class CLI
    # Writes a config tree into the provider, generating a value for every `__generate__` token,
    # and reports each key as added or changed as it goes.
    #
    # `current_values` is the flat set of values already in the store, which decides both which keys
    # are new and which keys may be skipped as unchanged. It is passed in rather than read here, so
    # that this class needs nothing but a provider to write through.
    class Importer
      attr_reader :provider, :random_size

      def initialize(provider:, random_size:)
        @provider    = provider
        @random_size = random_size
      end

      def import(config, path, current_values = {}, prune: false, force: false)
        delete_keys = prune ? current_values.keys - Utils.flatten(config, path).keys : []

        unless delete_keys.empty?
          puts "Going to delete the following keys:"
          delete_keys.each { |key| puts "  #{key}" }
          sleep(5)
        end

        set_config(config, path, current_values, force: force)

        delete_keys.each do |key|
          puts "#{Colors::REMOVE}- #{key}#{Colors::CLEAR}"
          provider.delete(key)
        end
      end

      # `force` writes every key, including unchanged ones, so that they are re-encrypted under a new KMS key.
      # It must not affect anything else that reads `current_values`, in particular the `RANDOM` guard below:
      # regenerating a persisted secret during a key rotation would silently invalidate it.
      def set_config(config, path, current_values = {}, force: false)
        Utils.flatten_each(config, path) do |key, value|
          next if value.nil?
          next if !force && current_values[key].to_s == value.to_s

          if (size = generate_size(key, value))
            next if current_values.key?(key)

            value = random_password(size)
          elsif value == FILTERED
            # Ignore filtered values
            next
          end

          if current_values.key?(key)
            puts "#{Colors::KEY}* #{key}#{Colors::CLEAR}"
          else
            puts "#{Colors::ADD}+ #{key}#{Colors::CLEAR}"
          end

          provider.set(key, value)
        end
      end

      private

      # Returns the size in bytes to generate for `value`, or nil when it is not a generate token.
      # `__generate__` uses `--random_size`, `__generate__:64` overrides it for this key alone.
      # A near miss such as `__generate__:abc` raises rather than being imported literally, since it is
      # far more likely to be a typo than an intended value.
      def generate_size(key, value)
        value = value.to_s.strip

        if value == RANDOM
          SecretConfig.deprecation_warning(
            "`#{RANDOM}` is deprecated in favor of `#{SecretConfig::GENERATE}`, which is not so easily " \
            "confused with the `${random}` interpolation. Update the value of `#{key}`."
          )
          return random_size
        end

        return nil unless value.start_with?(SecretConfig::GENERATE)

        match = SecretConfig::GENERATE_PATTERN.match(value)
        unless match
          raise ArgumentError,
                "Invalid generate token #{value.inspect} for key #{key.inspect}. " \
                "Expected `#{SecretConfig::GENERATE}` or `#{SecretConfig::GENERATE}:size`, for example `#{SecretConfig::GENERATE}:64`."
        end

        match[1]&.to_i || random_size
      end

      def random_password(size = random_size)
        SecureRandom.urlsafe_base64(size)
      end
    end
  end
end
