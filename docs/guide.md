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

Replace the sensitive data with a `SecureConfig.fetch`:

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
