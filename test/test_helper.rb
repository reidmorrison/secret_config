$LOAD_PATH.unshift File.dirname(__FILE__) + "/../lib"

# Defines CGI up front so that amazing_print's `autoload :CGI, "cgi"` is a no-op.
# Ruby 4.0 removed cgi from the stdlib, leaving a shim that warns and re-requires
# cgi/escape while it is still loading. Present in stdlib since Ruby 2.7.
require "cgi/escape"

# Must be started before `secret_config` is required so that every line is tracked.
require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
end

require "yaml"
require "minitest/autorun"
require "minitest/mock"
require "minitest/reporters"
require "secret_config"
require "amazing_print"

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
