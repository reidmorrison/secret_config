# Secret Config
[![Gem Version](https://img.shields.io/gem/v/secret_config.svg)](https://rubygems.org/gems/secret_config) [![Build Status](https://travis-ci.org/rocketjob/secret_config.svg?branch=master)](https://travis-ci.org/rocketjob/secret_config) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Gitter chat](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Centralized Configuration and Secrets Management for Ruby and Rails applications.

Securely store configuration information centrally, supporting multiple tenants of the same application.

## v0.9 Upgrade Notes

Note that the command line program name has changed from `secret_config` to `secret-config`. 
Be careful that the arguments have also changed. The arguments are now consistent across operations.
The command line examples below have also been updated to reflect the changes. 
 
Please run `secret-config --help` to see the new arguments and updated operations.  

## Overview

Securely store centralized configuration information such as:
* Settings
* Passwords
* Encryption keys and certificates

## Features

Supports storing configuration information in:
* File
    * Development and testing use.
* Environment Variables
    * Environment Variables take precedence and can be used to override any setting.
* AWS System Manager Parameter Store
    * Encrypt and securely store secrets such as passwords centrally.

Since all values are stored as strings in the central directory or config file, the following type conversions 
are supported:
* integer
* float
* string
* boolean
* symbol
* json

Supported conversions:
* base64

Arrays are also supported when the value contains a known separator by which to break down the values.

## Benefits

Benefits of moving sensitive configuration information into AWS System Manager Parameter Store:

  * Hierarchical structure is maintained.
    * Environment variables force all config into a single level.
  * Reduces the number of environment variables.
    * In a large application the number of secrets can grow dramatically.
  * Replaces sensitive data stored in local yaml or configuration files.
    * Including securing and managing encryption keys.
  * When encryption keys change, such as during a key rotation, config files don't have to be changed.
  * Removes security concerns with placing passwords in the clear into environment variables.
  * AWS System Manager Parameter Store does not charge for parameters.
    * Still recommend using a custom KMS key that charges only $1 per month.
    * Amounts as of 4/2019. Confirm what AWS charges you for these services.
  * AWS Secrets Manager charges for every secret being managed, which can accumulate quickly with large projects.
  * Configure multiple distinct application instances to support multiple tenants.
    * For example, use separate databases with unique credentials for each tenant.
  * Separation of responsibilities is achieved since operations can manage production configuration.
    * Developers do not need to be involved with production configuration such as host names and passwords.
  * All values are encrypted by default when stored in the AWS Parameter Store.
    * Prevents accidentally not encrypting sensitive data.

## Introduction

When Secret Config starts up it reads all configuration entries into memory for all keys under the configured path.
This means that once Secret Config has initialized all calls to Secret Config are extremely fast.

The in-memory copy of the registry can be refreshed at any time by calling `SecretConfig.refresh!`. It can be refreshed
via a process signal, or by calling it through an event, or via a messaging system.

It is suggested that any programmatic lookup to values stored in Secret Config are called every time a value is
being used, rather than creating a local copy of the value. This ensures that a refresh of the registry will take effect
immediately for any code reading from Secret Config.

## API

When Secret Config starts up it reads all configuration entries immediately for all keys under the configured path.
This means that once Secret Config has initialized all calls to Secret Config are extremely fast.

Secret Config supports the following programmatic interface:

### Read values

Fetch the value for the supplied key, returning nil if not found:

~~~ruby
# Key is present:
SecretConfig["logger/level"]
# => "info"

# Key is missing:
SecretConfig["logger/blah"]
# => nil
~~~

Fetch the value for the supplied key, raising `SecretConfig::MissingMandatoryKey` if not found:

~~~ruby
# Key is present:
SecretConfig.fetch("logger/level")
# => "info"

# Key is missing:
SecretConfig.fetch("logger/blah")
# => SecretConfig::MissingMandatoryKey (Missing configuration value for /development/logger/blah)
~~~

A default value can be supplied when the key is not found in the registry:

~~~ruby
SecretConfig.fetch("logger/level", default: "info")
# => "info"
~~~

Since AWS SSM Parameter store and environment variables only support string values,
it is neccessary to convert the string back to the type required by the program.

The following types are supported:
    `:integer`
    `:float`
    `:string`
    `:boolean`
    `:symbol`
    `:json`

~~~ruby
# Without type conversion:
SecretConfig.fetch("symmetric_encryption/version")
# => "0"

# With type conversion:
SecretConfig.fetch("symmetric_encryption/version", type: :integer)
# => 0
~~~

Sometimes it is useful to store arrays of values as a single key.  

~~~ruby
# Example: A list of host names could be stored as: "primary.example.net,secondary.example.net,backup.example.net"
# To extract it as an array of strings: 
SecretConfig.fetch("address_services/hostnames", separator: ",")
# => ["primary.example.net", "secondary.example.net", "backup.example.net"]

# Example: A list of ports could be stored as: "12345,5343,26815"
# To extract it as an array of Integers: 
SecretConfig.fetch("address_services/ports", type: :integer, separator: ",")
# => [12345, 5343, 26815]
~~~

When storing binary data, it should be encoded with strict base64 encoding. To automatically convert it back to binary
specify the encoding as `:base64`

~~~ruby
# Return a value that was stored in Base64 encoding format:
SecretConfig.fetch("symmetric_encryption/iv")
# => "FW+/wLubAYM+ZU0bWQj59Q=="

# Base64 decode a value that was stored in Base64 encoding format:
SecretConfig.fetch("symmetric_encryption/iv", encoding: :base64)
# => "\x15o\xBF\xC0\xBB\x9B\x01\x83>eM\eY\b\xF9\xF5"
~~~

### Key presence

Returns whether a key is present in the registry:

~~~ruby
SecretConfig.key?("logger/level")
# => true
~~~

### Write values

When Secret Config is configured to use the AWS SSM Parameter store, its values can be modified:

~~~ruby
SecretConfig["logger/level"] = "debug"
~~~

~~~ruby
SecretConfig.set("logger/level", "debug")
~~~

### Configuration

Returns a Hash copy of the configuration as a tree:

~~~ruby
SecretConfig.configuration
~~~

### Refresh Configuration

Tell Secret Config to refresh its in-memory copy of the configuration settings.

~~~ruby
SecretConfig.refresh!
~~~

Example, refresh the registry any time a SIGUSR2 is raised, add the following code on startup:

~~~ruby
Signal.trap('USR2') do
  SecretConfig.refresh!
end
~~~

Then to make the process refresh it registry:
~~~shell
kill -SIGUSR2 1234
~~~

Where `1234` above is the process PID.

## Development and Test use

In the development environment create the file `config/application.yml` within which to store local development credentials.
Depending on your team setup you may want to use the same file for all developers so can check it into you change control system.

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

Note how the hierarchical nature of configuration values is maintained. Typical environment variable approaches have
to flatten everything into a single level.

Note: Do not put any production credentials into this file.

### Environment Variables

Any of the above values can be overridden with an environment variable, unless explicitly configured `SecretConfig.check_env_var = false`.

To overwrite any of these settings with an environment variable:

* Join the keys together with an '_'
* Convert to uppercase

For example, `mysql/host` can be overridden with the env var:

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

## Configuration

Add the following line to Gemfile

    gem "secret_config"

Out of the box Secret Config will look in the local file system for the file `config/application.yml`
as covered above. By default it will use env var `RAILS_ENV` to define the path to look under for settings.

The default settings are great for getting started in development and test, but should not be used in production.

To ensure Secret Config is configured and available for use within any of the config files, add
the following lines to the very top of `application.rb` under the line `class Application < Rails::Application`:

~~~ruby
module MyApp
  class Application < Rails::Application

    # Add the following lines to configure Secret Config:
    if Rails.env.development? || Rails.env.test?
      # Use 'config/application.yml'
      config.secret_config.use :file
    else
      # Read configuration from AWS SSM Parameter Store
      config.secret_config.use :ssm, path: "/#{Rails.env}/my_app"
    end

    # ....
  end
end
~~~

`path` is the path from which the configuration data will be read. This path uniquely identifies the
configuration for this instance of the application. In the example above it uses the rails env and application name
by default. This can be overridden using the `SECRET_CONFIG_PATH` environment variable when needed.

By placing the secret config configuration as the very first configuration item, it allows any subsequent
configuration item to access the centralized configuration in AWS System Manager Parameter Store.

The environment variable `SECRET_CONFIG_PROVIDER` can be used to override the provider when needed.
For example:
    `export SECRET_CONFIG_PROVIDER=ssm`
Or,
    `export SECRET_CONFIG_PROVIDER=file`

If we need 2 completely separate instances of the application running in a single AWS account then we could use
multiple paths. For example:

    /production1/my_application
    /production2/my_application

    /production/instance1/my_application
    /production/instance2/my_application

The `path` is completely flexible, but must be unique for every AWS account under which the application will run.
The same `path` can be used in different AWS accounts though. It is also not replicated across regions.

When writing settings to the parameter store, it is recommended to use a custom KMS key to encrypt the values, if you don't specify a key ID, the system uses the default key associated with your AWS account `alias/aws/ssm`.
To supply the key to encrypt the values with, add the `key_id` parameter:

~~~ruby
module MyApp
  class Application < Rails::Application

    # Add the following lines to configure Secret Config:
    if Rails.env.development? || Rails.env.test?
      # Use 'config/application.yml'
      config.secret_config.use :file
    else
      # Read configuration from AWS SSM Parameter Store
      config.secret_config.use :ssm,
        path: "/#{Rails.env}/my_app",
        key_id: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    end

    # ....
  end
end
~~~

Note: The relevant KMS key must be created first prior to using it here.

`ssm` provider supports various configuration parameters that can be provided as keyword arguments for `config.secret_config.use :ssm, path, **args`

Args hash:
* **:key_id** (String) - The `key_id` is only used when writing settings to the AWS Parameter store and can be left off when that instance will only read from the parameter store. Can be configred with environment variable `SECRET_CONFIG_KEY_ID`.
* **:retry_count** (Integer, default=10) - Max number of retries in case of execution failure.
* **:retry_max_ms** (Integer, default=3_000) - Interval in ms between retries, `sleep` is used to facilitate throttling.
* any options suported by [Aws::SSM::Client](https://docs.aws.amazon.com/sdkforruby/api/Aws/SSM/Client.html#initialize-instance_method) e.g. **:credentials**:
~~~ruby
  config.secret_config.use :ssm,
    path: "/#{Rails.env}/my_app",
    key_id: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
    credentials: Aws::AssumeRoleCredentials.new(
      role_arn:          "arn:aws:iam::111111122222222:role/assume_role_name",
      role_session_name: "session-name-to-identify-#{SecureRandom.uuid}"
    ))
~~~

### Secret Config Environment variables

Priority describes when environment variable is used as a default value, preceds configuration value or overrides.

 Name                      | Desctiption                                                     | Priority
 ------------------------- | --------------------------------------------------------------- | --------
 `SECRET_CONFIG_PATH`      | path from which the configuration data will be read             | precede
 `SECRET_CONFIG_PROVIDER`  | override the provider configured for `config.secret_config.use` | override
 `SECRET_CONFIG_KEY_ID`    | encryption `key_id`                                             | default
 `SECRET_CONFIG_ACCOUNT_ID`| used in `rspec` to configure AWS Account Id for role assuming   | required

### Shared configuration for development and test

When running multiple engines or private "gems" inside the same code repository, the development and test
configuration file `application.yml` can be shared. Update the lines above to:

~~~ruby
module MyApp
  class Application < Rails::Application

    # Add the following lines:
    if Rails.env.development? || Rails.env.test?
      # Use 'config/application.yml'
      config.secret_config.use :file
    else
      # Read configuration from AWS SSM Parameter Store
      config.secret_config.use :ssm, path: "/#{Rails.env}/my_app"
    end

    # ....
  end
end
~~~

Where `file_name` is the full path and filename for where `application.yml` is located.

### Authorization

The following policy needs to be added to the IAM Group under which the application will be running:

~~~json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ssm:GetParametersByPath",
                "ssm:PutParameter",
                "ssm:DeleteParameter",
            ],
            "Resource": "*"
        }
    ]
}
~~~

The above policy restricts read and write access to just the Parameter Store capabilities of AWS System Manager.

These additional Actions are not used by Secret Config, but may be useful for anyone using the AWS Console directly
to view and modify parameters:
- `ssm:DescribeParameters`
- `ssm:GetParameterHistory`
- `ssm:GetParameters`
- `ssm:GetParameter`

## String Interpolation

Values supplied for config settings can be replaced inline with date, time, hostname, pid and random values.

For example to include the `hostname` in the log file name setting:

~~~yaml
development:
  logger:
    level:     info
    file_name: /var/log/my_application_%{hostname}.log
~~~

Available interpolations:

* %{date}
    * Current date in the format of "%Y%m%d" (CCYYMMDD)
* %{date:format}
    * Current date in the supplied format. See strftime
* %{time}
    * Current date and time down to ms in the format of "%Y%m%d%Y%H%M%S%L" (CCYYMMDDHHMMSSmmm)
* %{time:format}
    * Current date and time in the supplied format. See strftime
* %{env:name}
    * Extract value from the named environment variable.
* %{hostname}
    * Full name of this host.
* %{hostname:short}
    * Short name of this host. Everything up to the first period.
* %{pid}
    * Process Id for this process.
* %{random}
    * URL safe Random 32 byte value.
* %{random:size}
    * URL safe Random value of `size` bytes.

#### Notes:

* To prevent interpolation use %%{...}
* %% is not touched, only %{...} is searched for.
* Since these interpolations are only evaluated at load time and
  every time the registry is refreshed there is no runtime overhead when keys are fetched.

## Command Line Interface

Secret Config has a command line interface for exporting, importing and copying between paths in the registry.

~~~
secret-config [options]
    -e, --export SOURCE_PATH         Export configuration. Use --file to specify the file name, otherwise stdout is used.
    -i, --import TARGET_PATH         Import configuration. Use --file to specify the file name, --path for the SOURCE_PATH, otherwise stdin is used.
        --file FILE_NAME             Import/Export/Diff to/from this file.
    -p, --path PATH                  Import/Export/Diff to/from this path.
        --diff TARGET_PATH           Compare configuration to this path. Use --file to specify the source file name, --path for the SOURCE_PATH, otherwise stdin is used.
    -s, --set KEY=VALUE              Set one key to value. Example: --set mysql/database=localhost
    -f, --fetch KEY                  Fetch the value for one setting. Example: --fetch mysql/database.
    -d, --delete KEY                 Delete one specific key.
    -r, --delete-tree PATH           Recursively delete all keys under the specified path.
    -c, --console                    Start interactive console.
        --provider PROVIDER          Provider to use. [ssm | file]. Default: ssm
        --no-filter                  For --export only. Do not filter passwords and keys.
        --interpolate                For --export only. Evaluate string interpolation and __import__.
        --prune                      For --import only. During import delete all existing keys for which there is no key in the import file. Only works with --import.
        --force                      For --import only. Overwrite all values, not just the changed ones. Useful for changing the KMS key.
        --key_id KEY_ID              For --import only. Encrypt config settings with this AWS KMS key id. Default: AWS Default key.
        --key_alias KEY_ALIAS        For --import only. Encrypt config settings with this AWS KMS alias.
        --random_size INTEGER        For --import only. Size to use when generating random values when $(random) is encountered in the source. Default: 32
    -v, --version                    Display Secret Config version.
    -h, --help                       Prints this help.
~~~

### CLI Examples

#### Import from a file into SSM parameters

To get started it is useful to create a YAML file with all the relevant settings and then import
it into AWS SSM Parameter store. This file is the same as `applcation.yml` except that each file
is just for one environment. I.e. It does not contain the `test` or `development` root level entries.

For example: `production.yml`

~~~yaml
mysql:
  database:   secret_config_production
  username:   secret_config
  password:   secret_configrules
  host:       mysql_server.example.net

mongo:
  database:   secret_config_production
  primary:    mongo_primary.example.net:27017
  secondary:  mongo_secondary.example.net:27017

secrets:
  secret_key_base: somereallylongproductionstring
~~~

Import a yaml file, into a path in AWS SSM Parameter Store:

    secret-config --import /production/my_application --path  production.yml

Import a yaml file, into a path in AWS SSM Parameter Store, using a custom KMS key to encrypt the values:

    secret-config --import /production/my_application --path production.yml --key_id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

Import a yaml file, into a path in AWS SSM Parameter Store, using a custom KMS key alias to encrypt the values:

    secret-config --import /production/my_application --path production.yml --key_alias my_key_alias

#### Diff

Before importing a new config file into the AWS SSM Parameter store, a diff can be performed to determine
what the differences are that will be applied when the import is run with the `--prune` option.

    secret-config --diff /production/my_application --path production.yml 

Key:

    + Adding a new key to the registry.
    - The key will be removed from the registry during the import if --prune is specified.
    * The value for that key will change during an import.

#### Export SSM parameters

In AWS SSM Parameter store it can be difficult to
Export the values from a specific path into a yaml or json file so that they are easier to read.

Export from a path in AWS SSM Parameter Store to a yaml file, where passwords are filtered:

    secret-config --export /production/my_application --file production.yml 

Export from a path in AWS SSM Parameter Store to a yaml file, _without_ filtering out passwords:

    secret-config --export /production/my_application --file production.yml --no-filter

Export from a path in AWS SSM Parameter Store to a json file, where passwords are filtered:

    secret-config --export /production/my_application --file production.json 

#### Copy values between paths in AWS SSM parameter store

It can be useful to keep a "master" copy of the values for an environment or stack in a custom path
in AWS Parameter Store. Then for each stack or environment that is spun up, copy the "master" / "common" values
into the new path. Once copied the values specific to that path can be updated accordingly.

Import configuration from an existing path in AWS SSM Parameter Store into another:

    secret-config --import /tenant73/my_application --path /production/my_application 

#### Generating random passwords

In the multi-tenant example above, we may want to generate a secure random password for each tenant.
In the source file or registry, set the value to `$random`, this will ensure that during the `import` or `copy`
that the destination will receive a secure random value.

By default the length of the randomized value is 32 bytes, use `--random_size` to adjust the length of
the randomized string.

## Docker

Secret Config is at its best when the application is containerized. By externalizing the configuration the same
docker container can be tested in one or more environments and then deployed directly to production without
any changes. The only difference being the path that container uses to read its configuration from.

Another important benefit is that the docker image does not contain any production or test credentials since
these are all stored in AWS SSM Parameter Store.

When a Ruby / Rails application is using Secret Config for its configuration settings, it only requires the
following environment variables when starting up the container in for example AWS ECS or AWS Fargate:

~~~shell
export SECRET_CONFIG_PATH=/production/my_application
~~~

For rails applications, typically the `RAILS_ENV` is also needed, but not required for Secret Config.

~~~shell
export RAILS_ENV=production
~~~

### Logging

When using Semantic Logger, the following code could be added to `application.rb` to facilitate configuration
of the logging output via Secret Config:

~~~ruby
# Logging
config.log_level                       = config.secret_config.fetch("logger/level", default: :info, type: :symbol)
config.semantic_logger.backtrace_level = config.secret_config.fetch("logger/backtrace_level", default: :error, type: :symbol)
config.semantic_logger.application     = config.secret_config.fetch("logger/application", default: "my_app")
config.semantic_logger.environment     = config.secret_config.fetch("logger/environment", default: Rails.env)
~~~

In any environment the log level can be changed, for example set `logger/level` to `debug`. And it can be changed
in the AWS SSM Parameter Store, or directly with the environment variable `export LOGGER_LEVEL=debug`

`logger/environment` can be used to identify which tenant the log messages are emanating from. By default it is just
the rails environment. For example set `logger/environment` to `tenant73`.

Additionally the following code can be used with containers to send log output to standard out:

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

Specifically for docker containers it is necessary to turn off file logging and turn on logging to standard out
so that AWS Cloud Watch can pick up the log data.

To start with `logger/destination` of `stdout` will work with regular non-colorized output. When feeding the
log output into something that can process JSON, set `logger/formatter` to `json`.

The benefit with the above approach is that a developer can pull the exact same container image that is running
in production and configure it to run locally on their laptop. For example, set `logger/destination` to `file`.

The above code can be modified as necessary to add any Semantic Logger appender to write directly to external
centralized logging systems, instead of writing to standard out or local files.

### Email Server and Assets

An example of how to setup the email server and the assets for html emails. Add to `application.rb`:

~~~ruby
# Emails
application_url = config.secret_config.fetch("emails/asset_host")
uri             = URI.parse(application_url)

config.action_mailer.default_url_options   = {host: uri.host, protocol: uri.scheme}
config.action_mailer.asset_host            = application_url
config.action_mailer.smtp_settings         = {address: config.secret_config.fetch("emails/smtp/address", default: "localhost")}
config.action_mailer.raise_delivery_errors = config.secret_config.fetch("emails/raise_delivery_errors", default: true, type: :boolean)
~~~

### Symmetric Encryption

An example of how to setup Symmetric Encryption. Add to `application.rb`:

~~~ruby
# Encryption
config.symmetric_encryption.cipher =
  SymmetricEncryption::Cipher.new(
    key:     config.secret_config.fetch('symmetric_encryption/key', encoding: :base64),
    iv:      config.secret_config.fetch('symmetric_encryption/iv', encoding: :base64),
    version: config.secret_config.fetch('symmetric_encryption/version', type: :integer),
  )

# Also support one prior encryption key version during key rotation
if config.secret_config.key?('symmetric_encryption/old/key')
  SymmetricEncryption.secondary_ciphers = [
    SymmetricEncryption::Cipher.new(
      key:     config.secret_config.fetch('symmetric_encryption/old/key', encoding: :base64),
      iv:      config.secret_config.fetch('symmetric_encryption/old/iv', encoding: :base64),
      version: config.secret_config.fetch('symmetric_encryption/old/version', type: :integer),
    ),
  ]
end
~~~

Using this approach the file `config/symmetric-encryption.yml` can be removed once the keys have been moved to
the registry.

To extract existing keys from the config file so that they can be imported into the registry,
run the code below inside a console in each of the respective environments.

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

config = { "symmetric_encryption" => se_config(SymmetricEncryption.cipher) }
if cipher = SymmetricEncryption.secondary_ciphers.first
  config["symmetric_encryption"]["old"] = se_config(cipher)
end
puts config.to_yaml
~~~

## Versioning

This project adheres to [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison)

## License

Copyright 2019 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
