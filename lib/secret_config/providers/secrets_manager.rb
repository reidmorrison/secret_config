begin
  require "aws-sdk-secretsmanager"
rescue LoadError => e
  raise(LoadError, "Install gem 'aws-sdk-secretsmanager' to use AWS Secrets Manager: #{e.message}")
end

module SecretConfig
  module Providers
    # Use AWS Secrets Manager for Centralized Configuration / Secrets Management
    #
    # Beta. Feedback is wanted on https://github.com/reidmorrison/secret_config/issues/8, in particular
    # on whether one secret per setting is the right layout for the way Secrets Manager is actually used.
    #
    # One secret holds one setting, so that the tree is laid out exactly as it is in the SSM Parameter
    # Store and the two providers are interchangeable. Secrets Manager charges per secret per month,
    # which the Parameter Store does not, so read `docs/providers.md` before pointing an entire
    # configuration tree at it.
    class SecretsManager < Provider
      # `BatchGetSecretValue` returns at most 20 secrets per call, so the whole tree is read in
      # pages of this size.
      MAX_RESULTS = 20

      # The recovery window that `DeleteSecret` accepts, in days.
      RECOVERY_WINDOW_RANGE = (7..30)

      attr_reader :client, :key_id, :recovery_window_in_days, :logger

      # Parameters:
      #   key_id: [String]
      #     The KMS key to encrypt new secrets with. Defaults to the account key `aws/secretsmanager`.
      #
      #   key_alias: [String]
      #     The KMS key alias to encrypt new secrets with. Takes precedence over `key_id`.
      #
      #   recovery_window_in_days: [Integer]
      #     How long a deleted secret can still be restored for, between 7 and 30 days.
      #     Secrets Manager has no immediate delete that also frees the name, so this cannot be
      #     turned off. See `#delete`.
      #
      # Any remaining arguments are passed to `Aws::SecretsManager::Client`.
      def initialize(
        key_id: ENV.fetch("SECRET_CONFIG_KEY_ID", nil),
        key_alias: ENV.fetch("SECRET_CONFIG_KEY_ALIAS", nil),
        recovery_window_in_days: RECOVERY_WINDOW_RANGE.max,
        **args
      )
        super()
        @key_id =
          if key_alias
            key_alias =~ %r{^alias/} ? key_alias : "alias/#{key_alias}"
          else
            key_id
          end

        unless RECOVERY_WINDOW_RANGE.cover?(recovery_window_in_days)
          raise(ArgumentError,
                "recovery_window_in_days must be between #{RECOVERY_WINDOW_RANGE.min} and " \
                "#{RECOVERY_WINDOW_RANGE.max}, received: #{recovery_window_in_days.inspect}")
        end

        @recovery_window_in_days = recovery_window_in_days
        @logger                  = SemanticLogger["Aws::SecretsManager"] if defined?(SemanticLogger)
        @client                  = Aws::SecretsManager::Client.new({logger: logger}.merge!(args))
      end

      # Yields the key with its absolute path and corresponding string value.
      #
      # Secrets Manager has no hierarchical listing, so the tree is read with a `name` filter, which
      # matches the beginning of the secret name. That is a plain string prefix and knows nothing about
      # the `/` separator, so `/production/my_app` also matches `/production/my_application/mysql/host`.
      # Only names under `path` as a directory are yielded, which is what `get_parameters_by_path`
      # returns for the SSM provider.
      def each(path)
        prefix = "#{path}/"
        token  = nil
        loop do
          resp = client.batch_get_secret_value(
            filters:     [{key: "name", values: [path]}],
            max_results: MAX_RESULTS,
            next_token:  token
          )
          raise_on_errors(path, resp.errors)

          resp.secret_values.each do |secret|
            next unless secret.name.start_with?(prefix)
            # A binary secret has no string value. Skip it rather than yielding nil, which the
            # registry would store and then hand back to the application as an empty setting.
            next if secret.secret_string.nil?

            yield(secret.name, secret.secret_string)
          end

          token = resp.next_token
          break if token.nil?
        end
      end

      # Writes the value, creating the secret when it does not exist yet.
      #
      # `update_secret` is tried first because updating is the common case once a tree has been
      # imported. It is also the only one of the two write calls that accepts a KMS key, so the key
      # stays under this provider's control on every write, the way `put_parameter` does for SSM.
      #
      # Every write creates a new version of the secret. Secrets Manager keeps 100 versions and does
      # not reclaim any that are under a day old, so avoid writing the same key in a tight loop.
      def set(key, value)
        client.update_secret(secret_id: key, secret_string: value.to_s, kms_key_id: key_id)
      rescue Aws::SecretsManager::Errors::ResourceNotFoundException
        client.create_secret(name: key, secret_string: value.to_s, kms_key_id: key_id)
      end

      # Schedules the key for deletion.
      # Nothing is done if the key was not found.
      #
      # Unlike `delete_parameter`, this does not take effect immediately. The secret stops being
      # readable and drops out of `each` right away, but the name stays reserved for
      # `recovery_window_in_days`, so a delete followed by a write of the same key fails until the
      # window elapses. `restore_secret` cancels the deletion during it.
      def delete(key)
        client.delete_secret(secret_id: key, recovery_window_in_days: recovery_window_in_days)
      rescue Aws::SecretsManager::Errors::ResourceNotFoundException
        # Deleting a key that is already absent is not an error.
      end

      # Returns the value or `nil` if not found
      def fetch(key)
        client.get_secret_value(secret_id: key).secret_string
      rescue Aws::SecretsManager::Errors::ResourceNotFoundException
        # A missing key returns nil rather than raising.
      end

      private

      # `batch_get_secret_value` reports a failure to read one secret in `errors` and returns 200 for
      # the rest, so an unreadable secret would otherwise be indistinguishable from one that is not
      # there. Raise instead of loading a configuration that is quietly missing settings.
      def raise_on_errors(path, errors)
        return if errors.nil? || errors.empty?

        details = errors.map { |error| "#{error.secret_id}: #{error.error_code} #{error.message}" }
        raise(ConfigurationError, "Failed to read #{errors.size} secret(s) under #{path}. #{details.join(', ')}")
      end
    end
  end
end
