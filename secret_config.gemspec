lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

# Maintain your gem's version:
require "secret_config/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name                  = "secret_config"
  s.version               = SecretConfig::VERSION
  s.platform              = Gem::Platform::RUBY
  s.authors               = ["Reid Morrison"]
  s.homepage              = "https://config.reidmorrison.com"
  s.summary               = "Ship the same image to every environment and tenant. " \
                            "Configuration and secrets come from one central store."
  s.description           = "Secret Config stores configuration settings and secrets centrally, " \
                            "supporting multiple tenants of the same application. Settings are read " \
                            "from AWS System Manager Parameter Store, or a local file during " \
                            "development and test, and can be overridden with environment variables."
  s.files                 = Dir["lib/**/*", "bin/*", "LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  s.license               = "Apache-2.0"
  s.required_ruby_version = ">= 3.2"
  s.bindir                = "bin"
  s.executables           = ["secret-config"]
  s.add_dependency "concurrent-ruby", "~> 1.0"
  s.metadata = {
    "bug_tracker_uri"       => "https://github.com/reidmorrison/secret_config/issues",
    "changelog_uri"         => "https://github.com/reidmorrison/secret_config/blob/v#{SecretConfig::VERSION}/CHANGELOG.md",
    "documentation_uri"     => "https://config.reidmorrison.com",
    "source_code_uri"       => "https://github.com/reidmorrison/secret_config/tree/v#{SecretConfig::VERSION}",
    "rubygems_mfa_required" => "true"
  }
end
