begin
  require 'aws-sdk-ssm'
rescue LoadError => exc
  raise(LoadError, "Install gem 'aws-sdk-ssm' to use AWS Parameter Store: #{exc.message}")
end

module SecretConfig
  module Providers
    # Use the AWS System Manager Parameter Store for Centralized Configuration / Secrets Management
    class Ssm
      attr_reader :client, :key_id

      def initialize(key_id: nil)
        @key_id = key_id
        logger  = SemanticLogger['Aws::SSM'] if defined?(SemanticLogger)
        @client = Aws::SSM::Client.new(logger: logger)
      end

      def each(path)
        token = nil
        loop do
          resp = client.get_parameters_by_path(
            path:            path,
            recursive:       true,
            with_decryption: true,
            next_token:      token
          )
          resp.parameters.each { |param| yield(param.name, param.value) }
          token = resp.next_token
          break if token.nil?
        end
      end

      def set(key, value, encrypt: true)
        client.put_parameter(
          name:      key,
          value:     value.to_s,
          type:      encrypt ? "SecureString" : "String",
          key_id:    key_id,
          overwrite: true
        )
      end
    end
  end
end
