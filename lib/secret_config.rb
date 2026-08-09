require "forwardable"
require "secret_config/version"
require "secret_config/errors"
require "secret_config/registry"
require "secret_config/railtie" if defined?(Rails)

# Centralized Configuration and Secrets Management for Ruby and Rails applications.
module SecretConfig
  # When a node is both a value and a hash/branch in the tree, put its value in its hash with the following key:
  NODE_KEY   = "__value__".freeze
  # A node with the following key imports the settings under the path it refers to into its parent node.
  IMPORT_KEY = "__import__".freeze
  FILTERED   = "[FILTERED]".freeze
  # A value of `__generate__` is replaced by the CLI during an `--import` with a generated random value,
  # which is then persisted. Unlike `${random}` it is evaluated once, not on every startup and `refresh!`.
  # An optional size in bytes may be supplied as `__generate__:64`, defaulting to `--random_size`.
  #
  # Deliberately not spelled `${generate}`, which cannot work: `StringInterpolator#parse` raises on any
  # `${...}` key it cannot dispatch, so the token would fail the whole registry load for any file that is
  # both a CLI import source and read by the file provider. Making it dispatch would not help either,
  # since `${...}` composes inside a larger string while this sentinel is whole-value only, so
  # `password_${generate}` would parse as valid and silently never generate anything.
  GENERATE   = "__generate__".freeze
  # The size must be a positive integer, so that `__generate__:0` is rejected rather than
  # silently storing an empty secret.
  GENERATE_PATTERN = /\A__generate__(?::([1-9]\d*))?\z/
  # Deprecated spelling of `GENERATE`, too easily confused with the `${random}` interpolation.
  # Still honored, with a warning. To be removed in the next major release.
  RANDOM = "$(random)".freeze

  module Providers
    autoload :File, "secret_config/providers/file"
    autoload :Provider, "secret_config/providers/provider"
    autoload :SecretsManager, "secret_config/providers/secrets_manager"
    autoload :Ssm, "secret_config/providers/ssm"
  end

  autoload :CLI, "secret_config/cli"
  autoload :Config, "secret_config/config"
  autoload :Parser, "secret_config/parser"
  autoload :SettingInterpolator, "secret_config/setting_interpolator"
  autoload :StringInterpolator, "secret_config/string_interpolator"
  autoload :Utils, "secret_config/utils"

  class << self
    extend Forwardable

    def_delegator :registry, :fetch
    def_delegator :registry, :configuration
    def_delegator :registry, :[]
    def_delegator :registry, :[]=
    def_delegator :registry, :key?
    def_delegator :registry, :set
    def_delegator :registry, :delete
    def_delegator :registry, :refresh!
  end

  # Which provider to use along with any arguments
  #
  # Parameters:
  #   path: [String]
  #     The root path to read the configuration from.
  #     Overriden by env var `SECRET_CONFIG_PATH` if present.
  #
  #   interpolate: [true|false]
  #     Whether to evaluate `${...}` interpolations and `__import__` when reading the configuration.
  #     Default: true
  #
  # Any remaining arguments are passed to the provider when it is instantiated.
  def self.use(provider, path: nil, interpolate: true, **args)
    @registry = SecretConfig::Registry.new(
      path:          path,
      provider:      provider,
      provider_args: args,
      interpolate:   interpolate
    )
  end

  # Fetch configuration in a block by supplying the root path once.
  #
  # Example:
  #   SecretConfig.configure("suppliers/kafka_service") do |config|
  #     Kafka::Client.new(
  #       seed_brokers:       config.fetch("brokers", separator: ","),
  #       delivery_interval:  config.fetch("delivery_interval", type: :integer, default: 0),
  #       delivery_threshold: config.fetch("delivery_threshold", type: :integer, default: 0),
  #       max_queue_size:     config.fetch("max_queue_size", type: :integer, default: 10_000),
  #       max_retries:        config.fetch("max_retries", type: :integer, default: -1),
  #       retry_backoffs:     config.fetch("retry_backoff", type: :integer, default: 0),
  #     )
  #   end
  #
  # If `SecretConfig.configure` was not used it would have looked like:
  #   Kafka::Client.new(
  #     seed_brokers:       SecretConfig.fetch("suppliers/kafka_service/brokers", separator: ","),
  #     delivery_interval:  SecretConfig.fetch("suppliers/kafka_service/delivery_interval", type: :integer, default: 0),
  #     delivery_threshold: SecretConfig.fetch("suppliers/kafka_service/delivery_threshold", type: :integer, default: 0),
  #     max_queue_size:     SecretConfig.fetch("suppliers/kafka_service/max_queue_size", type: :integer, default: 10_000),
  #     max_retries:        SecretConfig.fetch("suppliers/kafka_service/max_retries", type: :integer, default: -1),
  #     retry_backoffs:     SecretConfig.fetch("suppliers/kafka_service/retry_backoff", type: :integer, default: 0),
  #   )
  def self.configure(path)
    config = Config.new(path, registry)
    yield(config)
  end

  # Returns the global registry.
  # Unless `.use` was called above, it will default to a file provider.
  def self.registry
    @registry ||= SecretConfig::Registry.new
  end

  # Filters to apply when returning the configuration
  def self.filters
    @filters
  end

  def self.filters=(filters)
    @filters = filters
  end

  # Check the environment variables for a matching key and override the value returned from
  # the central registry.
  def self.check_env_var?
    @check_env_var
  end

  def self.check_env_var=(check_env_var)
    @check_env_var = check_env_var
  end

  # Warn once per distinct message about a deprecated feature.
  # Set `SECRET_CONFIG_SILENCE_DEPRECATIONS` to any value to suppress.
  def self.deprecation_warning(message)
    return if ENV.key?("SECRET_CONFIG_SILENCE_DEPRECATIONS")

    warn_once("Deprecation: #{message}")
  end

  # Warn once per distinct message.
  # Written to stderr so that it does not corrupt CLI output that is being piped or redirected.
  def self.warn_once(message)
    return unless @warnings.add?(message)

    warn("[secret_config] #{message}")
  end

  @check_env_var = true
  @filters       = [/password/i, /key\Z/i, /passphrase/i, /secret/i, /pwd\Z/i]
  @warnings      = Set.new
end
