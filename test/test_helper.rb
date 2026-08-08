$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

# Defines CGI up front so that amazing_print's `autoload :CGI, "cgi"` is a no-op.
# Ruby 4.0 removed cgi from the stdlib, leaving a shim that warns and re-requires
# cgi/escape while it is still loading. Present in stdlib since Ruby 2.7.
require "cgi/escape"

# Must be started before `secret_config` is required so that every line is tracked.
require "simplecov"
SimpleCov.start do
  skip "/test/"
  enable_coverage :branch
  # cli.rb and railtie.rb are autoloaded, so without this they are absent from the report entirely
  # rather than counted as uncovered, which overstates the total.
  cover "lib/**/*.rb"
end

require "yaml"
require "minitest/autorun"
require "minitest/mock"
require "minitest/reporters"
require "secret_config"
require "amazing_print"

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# Writable provider for exercising the `set` and `delete` paths, which the file provider does not support.
# Keys are stored exactly as the registry supplies them, so tests can assert on the absolute key.
class InMemoryProvider < SecretConfig::Providers::Provider
  attr_reader :hash

  def initialize(hash = {})
    super()
    @hash = hash.dup
  end

  def each(path)
    hash.each_pair { |key, value| yield(key, value) if key.start_with?(path) }
  end

  def set(key, value)
    hash[key] = value.to_s
  end

  def delete(key)
    hash.delete(key)
  end

  def fetch(key)
    hash[key]
  end
end
