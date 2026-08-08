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

desc "Regenerate docs/llms-full.txt from the docs markdown pages"
task :llms_full do
  pages  = %w[index guide api config providers interpolation cli rails testing upgrading]
  header = <<~HEADER
    # Secret Config - Complete Documentation

    > Secret Config is centralized configuration and secrets management for Ruby and Rails applications.

    This file concatenates every page of https://config.reidmorrison.com for consumption by AI assistants.
    It is generated from the markdown sources in docs/ by `bundle exec rake llms_full`; do not edit it directly.
    A per-page index is available at https://config.reidmorrison.com/llms.txt
  HEADER

  sections = pages.map do |page|
    text = File.read("docs/#{page}.md").
           sub(/\A---\n.*?\n---\n/m, ""). # Jekyll front matter
           gsub(/^\{:.*\}\n/, "").        # kramdown attribute lines ({:toc}, {:.no_toc}, ...)
           gsub(/^\* TOC\n/, "").
           gsub(/^\*\*Contents\*\*\n/, "").
           gsub(/^!\[.*\n/, "")           # images (relative paths, useless in plain text)
    "<!-- source: docs/#{page}.md -->\n\n#{text.strip}\n"
  end

  File.write("docs/llms-full.txt", ([header] + sections).join("\n\n---\n\n"))
  puts "Wrote docs/llms-full.txt (#{File.size('docs/llms-full.txt')} bytes)"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = true
end

RuboCop::RakeTask.new

# Tests run first so that a lint failure never masks a real test failure.
task default: %i[test rubocop]
