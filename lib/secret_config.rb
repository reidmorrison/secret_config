require 'sync_attr'
require 'secret_config/version'
require 'secret_config/errors'
require 'secret_config/registry'

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

  def self.root
    @root ||= ENV["SECRET_CONFIG_ROOT"] ||
      raise(UndefinedRootError, "Either set env var 'SECRET_CONFIG_ROOT' or call SecretConfig.root=")
  end

  def self.root=(root)
    @root     = root
    @registry = nil if @registry
  end

  # When provider is not supplied, returns the current provider instance
  # When provider is supplied, sets the new provider and stores any arguments
  def self.provider(provider = nil, **args)
    if provider.nil?
      return @provider ||= create_provider((ENV["SECRET_CONFIG_PROVIDER"] || :file).to_sym)
    end

    @provider      = create_provider(provider, args)
    @registry      = nil if @registry
  end

  def self.provider=(provider)
    @provider = provider
    @registry = nil if @registry
  end

  def self.registry
    @registry ||= SecretConfig::Registry.new(root: root, provider: provider)
  end

  private

  def self.create_provider(provider, args = nil)
    klass = constantize_symbol(provider)
    if args && args.size > 0
      klass.new(**args)
    else
      klass.new
    end
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
