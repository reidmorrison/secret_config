begin
  require "aws-sdk-ssm"
rescue LoadError => e
  raise(LoadError, "Install gem 'aws-sdk-ssm' to use AWS Parameter Store: #{e.message}")
end

module SecretConfig
  module Providers
    # Use the AWS System Manager Parameter Store for Centralized Configuration / Secrets Management
    class Ssm < Provider
      attr_reader :client, :key_id, :retry_count, :retry_max_ms, :logger

      def initialize(
        key_id: ENV["SECRET_CONFIG_KEY_ID"],
        key_alias: ENV["SECRET_CONFIG_KEY_ALIAS"],
        retry_count: 25,
        retry_max_ms: 10_000,
        **args
      )
        @key_id       =
          if key_alias
            key_alias =~ %r{^alias/} ? key_alias : "alias/#{key_alias}"
          else
            key_id
          end
        @retry_count  = retry_count
        @retry_max_ms = retry_max_ms
        @logger       = SemanticLogger["Aws::SSM"] if defined?(SemanticLogger)
        @client       = Aws::SSM::Client.new({logger: logger}.merge!(args))
      end

      # Yields the key with its absolute path and corresponding string value
      def each(path)
        retries = 0
        token   = nil
        loop do
          begin
            resp = client.get_parameters_by_path(
              path:            path,
              recursive:       true,
              with_decryption: true,
              next_token:      token
            )
          rescue Aws::SSM::Errors::ThrottlingException => e
            # The free tier allows 40 calls per second.
            # The Higher Throughput tier for additional cost is still limited to 100 calls per second.
            # Using a random formula since this limit is normally only exceeded during a high volume restart period
            # so we want to spread out the retries of the multiple servers.
            retries += 1
            if retry_count > retries
              sleep_seconds = rand(retry_max_ms) / 1000.0
              logger&.info("SSM Parameter Store GetParametersByPath API Requests throttle exceeded, retry: #{retries}, sleeping #{sleep_seconds} seconds.")
              sleep(sleep_seconds)
              retry
            end
            logger&.info("SSM Parameter Store GetParametersByPath API Requests throttle exceeded, retries exhausted.")
            raise(e)
          end

          resp.parameters.each { |param| yield(param.name, param.value) }
          token = resp.next_token
          break if token.nil?
        end
      end

      def set(key, value)
        client.put_parameter(
          name:      key,
          value:     value.to_s,
          type:      "SecureString",
          key_id:    key_id,
          overwrite: true,
          tier:      "Intelligent-Tiering"
        )
      end

      # Deletes the key.
      # Nothing is done if the key was not found.
      def delete(key)
        client.delete_parameter(name: key)
      rescue Aws::SSM::Errors::ParameterNotFound
      end

      # Returns the value or `nil` if not found
      def fetch(key)
        client.get_parameter(name: key, with_decryption: true).parameter.value
      rescue Aws::SSM::Errors::ParameterNotFound
      end
    end
  end
end
