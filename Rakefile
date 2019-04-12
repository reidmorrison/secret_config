require 'rake/testtask'
require_relative 'lib/secret_config/version'

task :gem do
  system 'gem build secret_config.gemspec'
end

task :publish => :gem do
  system "git tag -a v#{SecretConfig::VERSION} -m 'Tagging #{SecretConfig::VERSION}'"
  system 'git push --tags'
  system "gem push secret_config-#{SecretConfig::VERSION}.gem"
  system "rm secret_config-#{SecretConfig::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
  t.warning = true
end

task :default => :test
