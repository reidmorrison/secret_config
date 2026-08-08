---
layout: default
---

# Getting Started Guide

## Installation

Add the following line to Gemfile

    gem "secret_config"

Install Gem

    bundle install

## Development and Test environments

Create the file `config/application.yml` which is used to store local development and testing credentials.
The same file can be used by all developers and should be checked into the source control system (E.g. Git).

For example: `config/application.yml`

~~~yaml
development:
  mysql:
    database:   secret_config_development
    username:   secret_config
    password:   secret_configrules
    host:       127.0.0.1

  mongo:
    database:   secret_config_development
    primary:    127.0.0.1:27017
    secondary:  127.0.0.1:27018

  secrets:
    secret_key_base: somereallylongstring

test:
  mysql:
    database:   secret_config_test
    username:   secret_config
    password:   secret_configrules
    host:       127.0.0.1

  mongo:
    database:   secret_config_test
    primary:    127.0.0.1:27017
    secondary:  127.0.0.1:27018

  secrets:
    secret_key_base: somereallylongteststring
~~~

Notice how each of the above settings are grouped into hierarchies, which can go several levels deep.

#### Note: Do not put any production credentials in this file.

### Environment Variables

Any of the above values can be overridden with an environment variable, 
unless explicitly disabled with `SecretConfig.check_env_var = false`.

To overwrite any of these settings with an environment variable:

* Join the keys together with an '_'
* Convert to uppercase

For example, `mysql/host` can be overridden without changing the config file by setting the environment variable:

    export MYSQL_HOST=test.server

### Applying to existing config files

Go through all the configuration files and look for sensitive data such as passwords:

Example, an unchanged common `database.yml`:

~~~yaml
defaults: &defaults
  encoding: utf8
  adapter:  mysql2

development:
  <<:       *defaults
  database: secure_config_development
  username: jack
  password: jackrules
  host:     localhost

test:
  <<:       *defaults
  database: secure_config_test
  username: tester
  password: khjsdjhdsjhdsr32
  host:     test.server

production:
  <<:       *defaults
  database: secure_config_production
  username: product
  password: donotexpose45
  host:     production.server
~~~

Replace the sensitive data with a call to `SecretConfig.fetch`:

Updated `database.yml`:

~~~yaml
configuration: &configuration
  database: <%= SecretConfig.fetch("mysql/database") %>
  username: <%= SecretConfig.fetch("mysql/username") %>
  password: <%= SecretConfig.fetch("mysql/password") %>
  host:     <%= SecretConfig.fetch("mysql/host") %>
  encoding: utf8
  adapter:  mysql2

development:
  <<:       *configuration

test:
  <<:       *configuration

production:
  <<:       *configuration
~~~

Since the secrets are externalized the configuration between environments is simpler.

### Replacing custom config files

When writing new components or gems, instead of requiring a proprietary config file, refer
to the settings programmatically:

For example, somewhere in your codebase you need a persistent http connection:

~~~ruby
  def http_client
    @http_client ||=
      PersistentHTTP.new(
        name:         'HTTPClient',
        url:          SecretConfig.fetch('http_client/url'),
        logger:       logger,
        pool_size:    SecretConfig.fetch('http_client/pool_size', type: :integer, default: 10),
        warn_timeout: SecretConfig.fetch('http_client/warn_timeout', type: :float, default: 0.25),
        open_timeout: SecretConfig.fetch('http_client/open_timeout', type: :float, default: 30),
        read_timeout: SecretConfig.fetch('http_client/read_timeout', type: :float, default: 30),
        force_retry:  true
      )
  end
~~~

Then the application that uses the above library / gem just needs to add the relevant entries to their
`application.yml` file:

~~~yaml
http_client:
  url:          https://test.example.com
  pool_size:    20
  read_timeout: 300
~~~

This avoids a custom config file just for the above library.

Additionally the values can be overridden with environment variables at any time:

    export HTTP_CLIENT_URL=https://production.example.com

## Sharing settings with `__import__`

A key named `__import__` copies the settings under another path into its parent node. It is useful when
several nodes share most of their settings and differ in only a few.

~~~yaml
test:
  my_application:
    mongo:
      database:   secret_config_test
      primary:    127.0.0.1:27017
      secondary:  127.0.0.1:27018

    mongo_reporting:
      __import__: mongo
      primary:    reporting.example.net:27017
~~~

`mongo_reporting` ends up with `database` and `secondary` copied from `mongo`, and keeps its own
`primary`. The `__import__` key itself is removed and never appears in the registry.

Notes on how imports resolve:

* A relative value, such as `mongo` above, is resolved against the root path of the registry, not
  against the node doing the importing.
* An absolute value, such as `/test/my_application/mongo`, is read from the provider directly. This
  allows one application to import settings from a path outside of its own root.
    * Each absolute import is a separate call to the provider, so they are more expensive than
      relative ones.
* A key that already exists always wins over an imported one, which is what makes the override above
  work.
* A path that itself contains an `__import__` can be imported. It is resolved first, so the settings it
  brings in are imported too, no matter which of the two nodes is declared first.
* Imports must not form a cycle. Two nodes that import each other, or a node that imports itself, raise
  `SecretConfig::ConfigurationError`.
* Imports are only applied when interpolation is enabled, which is the default. The CLI leaves them
  in place on export unless `--interpolate` is supplied, which keeps an export re-importable.

## When a setting is both a value and a branch

A node can have a value of its own and still have children under it. In AWS SSM Parameter Store this
happens whenever both `/production/my_application/logger` and `/production/my_application/logger/level`
exist as parameters.

YAML cannot express that directly, so Secret Config uses the reserved key `__value__` for the value that
belongs to the node itself:

~~~yaml
test:
  my_application:
    logger:
      __value__: info
      level:     debug
~~~

Read it as the node, not as `__value__`:

~~~ruby
SecretConfig.fetch("logger")
# => "info"

SecretConfig.fetch("logger/level")
# => "debug"
~~~

`SecretConfig.configuration` and the CLI's `--export` render such nodes back out with `__value__`, so an
export can be edited and imported again without losing the node's own value.
