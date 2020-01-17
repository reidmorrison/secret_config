require "forwardable"
require "secret_config/version"
require "secret_config/errors"
require "secret_config/registry"
require "secret_config/railtie" if defined?(Rails)

# Centralized Configuration and Secrets Management for Ruby and Rails applications.
module SecretConfig
  # When a node is both a value and a hash/branch in the tree, put its value in its hash with the following key:
  NODE_KEY = "__value__".freeze
  FILTERED = "[FILTERED]".freeze
  RANDOM   = "$(random)".freeze

  module Providers
    autoload :File, "secret_config/providers/file"
    autoload :Provider, "secret_config/providers/provider"
    autoload :Ssm, "secret_config/providers/ssm"
  end

  autoload :CLI, "secret_config/cli"
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
    def_delegator :registry, :fetch
    def_delegator :registry, :set
    def_delegator :registry, :delete
    def_delegator :registry, :refresh!
  end

  # Which provider to use along with any arguments
  # The path will be overriden by env var `SECRET_CONFIG_PATH` if present.
  def self.use(provider, path: nil, **args)
    @registry = SecretConfig::Registry.new(path: path, provider: provider, provider_args: args)
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

  private

  @check_env_var = true
  @filters       = [/password/i, /key\Z/i, /passphrase/i]
end
