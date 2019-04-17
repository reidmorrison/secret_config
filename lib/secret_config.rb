require 'forwardable'
require 'secret_config/version'
require 'secret_config/errors'
require 'secret_config/registry'
require 'secret_config/railtie' if defined?(Rails)

# Centralized Configuration and Secrets Management for Ruby and Rails applications.
module SecretConfig
  module Providers
    autoload :File, 'secret_config/providers/file'
    autoload :Ssm, 'secret_config/providers/ssm'
  end

  class << self
    extend Forwardable

    def_delegator :registry, :fetch
    def_delegator :registry, :configuration
    def_delegator :registry, :[]
    def_delegator :registry, :[]=
    def_delegator :registry, :key?
    def_delegator :registry, :fetch
    def_delegator :registry, :set
    def_delegator :registry, :refresh!
  end

  # Which provider to use along with any arguments
  # The root will be overriden by env var `SECRET_CONFIG_ROOT` if present.
  def self.use(provider, root: nil, **args)
    @provider = create_provider(provider, args)
    @root     = ENV["SECRET_CONFIG_ROOT"] || root
    @registry = nil if @registry
  end

  def self.root
    @root ||= begin
      root = ENV["SECRET_CONFIG_ROOT"] || ENV["RAILS_ENV"]
      root = Rails.env if root.nil? && defined?(Rails) && Rails.respond_to?(:env)
      raise(UndefinedRootError, "Either set env var 'SECRET_CONFIG_ROOT' or call SecretConfig.use") unless root
      root = "/#{root}" unless root.start_with?('/')
      root
    end
  end

  # Returns the current provider.
  # If `SecretConfig.use` was not called previously it automatically use the file based provider.
  def self.provider
    @provider ||= begin
      create_provider(:file)
    end
  end

  def self.registry
    @registry ||= SecretConfig::Registry.new(root: root, provider: provider)
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
  @filters       = [/password/, 'key', /secret_key/]

  # Create a new provider instance unless it is alread a provider instance.
  def self.create_provider(provider, args = nil)
    return provider if provider.respond_to?(:each) && provider.respond_to?(:set)

    klass = constantize_symbol(provider)
    args && args.size > 0 ? klass.new(**args) : klass.new
  end

  def implementation
    @implementation ||= constantize_symbol(provider).new
  end

  def self.constantize_symbol(symbol, namespace = 'SecretConfig::Providers')
    klass = "#{namespace}::#{camelize(symbol.to_s)}"
    begin
      Object.const_get(klass)
    rescue NameError
      raise(ArgumentError, "Could not convert symbol: #{symbol.inspect} to a class in: #{namespace}. Looking for: #{klass}")
    end
  end

  # Borrow from Rails, when not running Rails
  def self.camelize(term)
    string = term.to_s
    string = string.sub(/^[a-z\d]*/, &:capitalize)
    string.gsub!(/(?:_|(\/))([a-z\d]*)/i) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).capitalize}" }
    string.gsub!('/'.freeze, '::'.freeze)
    string
  end
end
