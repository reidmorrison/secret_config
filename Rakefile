require "rake/testtask"
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

task default: :test
