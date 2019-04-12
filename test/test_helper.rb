$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'yaml'
require 'minitest/autorun'
require 'minitest/reporters'
require 'secret_config'
require 'awesome_print'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
