require "rake/testtask"
require "rubocop/rake_task"
require_relative "lib/secret_config/version"

desc "Build the gem"
task :gem do
  system "gem build secret_config.gemspec"
end

desc "Build the gem, tag the release, and push it to rubygems"
task publish: :gem do
  system "git tag -a v#{SecretConfig::VERSION} -m 'Tagging #{SecretConfig::VERSION}'"
  system "git push --tags"
  system "gem push secret_config-#{SecretConfig::VERSION}.gem"
  system "rm secret_config-#{SecretConfig::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = true
end

RuboCop::RakeTask.new

# Tests run first so that a lint failure never masks a real test failure.
task default: %i[test rubocop]
