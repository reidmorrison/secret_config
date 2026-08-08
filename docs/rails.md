---
layout: default
---

## Rails
{:.no_toc}

**Contents**

* TOC
{:toc}

In a Rails application, Secret Config is set up once in `application.rb` and is then available to every
initializer, every `.yml` file, and the application itself.

The gem ships a railtie that exposes `config.secret_config`, which is the same `SecretConfig` singleton
under a name that fits the Rails configuration style. No `require` is needed.

## Step 1: Configure it in `application.rb`

Add this as the **first** configuration item, directly under
`class Application < Rails::Application`:

~~~ruby
module MyApp
  class Application < Rails::Application
    # Configure Secret Config before anything else, so that every configuration
    # item below can read from it.
    if Rails.env.development? || Rails.env.test?
      # Read config/application.yml
      config.secret_config.use :file
    else
      # Read from AWS SSM Parameter Store
      config.secret_config.use :ssm, path: "/#{Rails.env}/my_app"
    end

    # ... the rest of the application configuration
  end
end
~~~

Order matters. Anything above this line cannot read a setting, and everything below it can.

Note that the file provider is given no `path:`. Absent one it falls back to `RAILS_ENV`, then
`Rails.env`, so `config/application.yml` is read under the current environment name. The SSM provider
gets an explicit path, because the environment name alone is not specific enough to identify one
application's configuration in a shared AWS account.

`path` can always be overridden at deploy time with `SECRET_CONFIG_PATH`, which is what makes one image
run in several environments. See [Configuration](config).

## Step 2: Use a custom KMS key

The account default key `alias/aws/ssm` works, but a key of your own can be rotated on its own
schedule, which is generally what a compliance regime asks for:

~~~ruby
config.secret_config.use :ssm,
  path:   "/#{Rails.env}/my_app",
  key_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
~~~

The key must exist before it is named here. See [Providers](providers) for `key_alias:`, retries, and
the IAM policy the application needs.

## Step 3: Convert `database.yml`

Replace the credentials with calls to `fetch`. The three environments collapse into one block, because
what differed between them has moved into the store:

~~~yaml
configuration: &configuration
  encoding: utf8
  adapter:  mysql2
  database: <%= SecretConfig.fetch("mysql/database") %>
  username: <%= SecretConfig.fetch("mysql/username") %>
  password: <%= SecretConfig.fetch("mysql/password") %>
  host:     <%= SecretConfig.fetch("mysql/host") %>
  pool:     <%= SecretConfig.fetch("mysql/pool_size", type: :integer, default: 5) %>

development:
  <<: *configuration

test:
  <<: *configuration

production:
  <<: *configuration
~~~

Use `SecretConfig` rather than `config.secret_config` here. The `.yml` files are ERB-evaluated outside
the application configuration block, where `config` is not in scope.

## Step 4: Share one settings file across engines

When several engines or private gems live in one repository, they can share a single development and
test file rather than each carrying its own:

~~~ruby
config.secret_config.use :file, file_name: "../../../config/application.yml"
~~~

`file_name` is the path to the shared `config/application.yml`, relative to the engine.

## Deployment

### Containers

Secret Config is at its best in a container. The configuration is outside the image, so the same image
that passed testing is the one that goes to production, and the only thing that differs is the path it
reads from.

A container needs one environment variable:

~~~shell
export SECRET_CONFIG_PATH=/production/my_application
~~~

Rails itself usually wants `RAILS_ENV` as well, though Secret Config does not require it once
`SECRET_CONFIG_PATH` is set:

~~~shell
export RAILS_ENV=production
~~~

That is the whole deployment configuration. No credentials in the image, no credentials in the task
definition, and a developer can run the production image locally against a development path.

To run the same image for a second tenant, change one variable:

~~~shell
export SECRET_CONFIG_PATH=/production/tenant73/my_application
~~~

### Refreshing without a deploy

Because settings are read from the store rather than baked in, a value can be changed and picked up by
running processes without a deploy. Wire `refresh!` to a signal on startup:

~~~ruby
Signal.trap("USR2") do
  SecretConfig.refresh!
end
~~~

See [Guide, Step 10](api#step-10-refresh-at-runtime).

## Worked examples

These are the `application.rb` blocks that come up most often. All of them go below the
`config.secret_config.use` line from Step 1.

### Logging

With [Semantic Logger](https://logger.reidmorrison.com/), the whole logging setup becomes configuration:

~~~ruby
config.log_level                       = config.secret_config.fetch("logger/level", default: :info, type: :symbol)
config.semantic_logger.backtrace_level = config.secret_config.fetch("logger/backtrace_level", default: :error, type: :symbol)
config.semantic_logger.application     = config.secret_config.fetch("logger/application", default: "my_app")
config.semantic_logger.environment     = config.secret_config.fetch("logger/environment", default: Rails.env)
~~~

The log level can now be raised in any environment by changing `logger/level` in the store, or with
`export LOGGER_LEVEL=debug`, without a deploy.

`logger/environment` is useful for identifying which tenant a log entry came from. It defaults to the
Rails environment; set it to `tenant73` and every entry says so.

For containers, send output to standard out so the platform can collect it:

~~~ruby
destination = config.secret_config.fetch("logger/destination", default: :file, type: :symbol)
if destination == :stdout
  STDOUT.sync                                    = true
  config.rails_semantic_logger.add_file_appender = false
  config.semantic_logger.add_appender(
    io:        STDOUT,
    level:     config.log_level,
    formatter: config.secret_config.fetch("logger/formatter", default: :default, type: :symbol)
  )
end
~~~

Set `logger/destination` to `stdout` for plain output, and `logger/formatter` to `json` when feeding
something that parses JSON. A developer running the same image locally sets `logger/destination` back to
`file`.

### Email

~~~ruby
application_url = config.secret_config.fetch("emails/asset_host")
uri             = URI.parse(application_url)

config.action_mailer.default_url_options   = {host: uri.host, protocol: uri.scheme}
config.action_mailer.asset_host            = application_url
config.action_mailer.smtp_settings         = {address: config.secret_config.fetch("emails/smtp/address", default: "localhost")}
config.action_mailer.raise_delivery_errors = config.secret_config.fetch("emails/raise_delivery_errors", default: true, type: :boolean)
~~~

### Symmetric Encryption

Encryption keys are binary, so they are stored base64-encoded and decoded on the way out:

~~~ruby
config.symmetric_encryption.cipher =
  SymmetricEncryption::Cipher.new(
    key:     config.secret_config.fetch("symmetric_encryption/key", encoding: :base64),
    iv:      config.secret_config.fetch("symmetric_encryption/iv", encoding: :base64),
    version: config.secret_config.fetch("symmetric_encryption/version", type: :integer)
  )

# Also support one prior encryption key version during key rotation
if config.secret_config.key?("symmetric_encryption/old/key")
  SymmetricEncryption.secondary_ciphers = [
    SymmetricEncryption::Cipher.new(
      key:     config.secret_config.fetch("symmetric_encryption/old/key", encoding: :base64),
      iv:      config.secret_config.fetch("symmetric_encryption/old/iv", encoding: :base64),
      version: config.secret_config.fetch("symmetric_encryption/old/version", type: :integer)
    )
  ]
end
~~~

`config/symmetric-encryption.yml` can be deleted once the keys are in the store. Note the `key?` guard:
the secondary cipher only exists during a rotation, which is exactly the case
[`key?`](api#step-7-ask-whether-a-key-is-set) is for.

To get the existing keys out of the old config file so they can be imported, run this in a console in
each environment:

~~~ruby
require "yaml"
require "base64"

def se_config(cipher)
  {
    "key"     => Base64.strict_encode64(cipher.send(:key)),
    "iv"      => Base64.strict_encode64(cipher.iv),
    "version" => cipher.version
  }
end

config = {"symmetric_encryption" => se_config(SymmetricEncryption.cipher)}
if (cipher = SymmetricEncryption.secondary_ciphers.first)
  config["symmetric_encryption"]["old"] = se_config(cipher)
end
puts config.to_yaml
~~~

Feed the output to `secret-config --import`. Note that a base64 value ends in `=`, which `--set`
handles, but importing the file is easier than setting the keys one at a time. See
[Command Line](cli).

## Next steps

* [Configuration](config): every `use` option and startup environment variable.
* [Providers](providers): KMS keys, the IAM policy, and Parameter Store limits.
* [Testing](testing): controlling settings from the test suite.
