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
    @root ||= ENV["SECRETCONFIG_ROOT"] ||
      raise(UndefinedRootError, "Either set env var 'SECRETCONFIG_ROOT' or call SecretConfig.root=")
  end

  def self.root=(root)
    @root     = root
    @registry = nil if @registry
  end

  def self.provider #(provider, **args)
    @provider ||= (ENV["SECRETCONFIG_PROVIDER"] || :file).to_sym
  end

  def self.provider=(provider)
    @provider = provider
    @registry = nil if @registry
  end

  def self.registry
    @registry ||= SecretConfig::Registry.new(root: root, provider: provider)
  end
end
