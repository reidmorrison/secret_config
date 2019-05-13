# Secret Config
[![Gem Version](https://img.shields.io/gem/v/secret_config.svg)](https://rubygems.org/gems/secret_config) [![Build Status](https://travis-ci.org/rocketjob/secret_config.svg?branch=master)](https://travis-ci.org/rocketjob/secret_config) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Gitter chat](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Centralized Configuration and Secrets Management for Ruby and Rails applications.

Securely store configuration information centrally, supporting multiple tenants of the same application.

## Features

Supports storing configuration information in:
* File
    * Development and testing use.
* AWS System Manager Parameter Store
    * Encrypt and store secrets such as passwords centrally. 

## Benefits

Benefits of moving sensitive configuration information into AWS System Manager Parameter Store:

  * Hierarchical structure is maintained.
    * Environment variables force all config into a single level.
  * Reduces the number of environment variables.
    * In a large application the number of secrets can grow dramatically.
  * Removes the need to encrypt sensitive data config files.
    * Including securing and managing encryption keys.
  * When encryption keys change, such as during a key rotation, config files don;t have to be changed.
  * Removes security concerns with placing passwords in the clear into environment variables.
  * AWS System Manager Parameter Store does not charge for parameters.
    * Still recommend using a custom KMS key that charges only $1 per month.
    * Amounts as of 4/2019. Confirm what AWS charges you for these services.
  * AWS Secrets Manager charges for every secret being managed, which can accumulate quickly with large projects.
  * Configure multiple distinct application instances to support multiple tenants.
    * For example, use separate databases with unique credentials for each tenant.    
  
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

Any of the above values can be overridden with an environment variable.

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

When writing settings to the parameter store, it is recommended to use a custom KMS key to encrypt the values.
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
        key_id: 'xxxxx-xxxxxx-xxxxx'
    end    
    
    # ....
  end
end
~~~

Note: The relevant KMS key must be created first prior to using it here.

The `key_id` is only used when writing settings to the AWS Parameter store and can be left off when that instance
will only read from the parameter store.

### Shared configuration for development and test

When running multiple engines or private "gems" inside the same code repository, the development and test
configuration file `application.yml` can be shared. Update the lines above to:

~~~ruby
module MyApp
  class Application < Rails::Application
  
    # Add the following lines:
    if Rails.env.development? || Rails.env.test?
      config.secret_config.use :file, file_name: File.expand_path('../../application.yml', __dir__)
    else 
      # Read configuration from AWS Parameter Store
      config.secret_config.use :ssm, path: '/production/my_application'
    end
    
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

## Command Line Interface

Secret Config has a command line interface for exporting, importing and copying between paths in the registry.

~~~
secret_config [options]
    -e, --export [FILE_NAME]         Export configuration to a file or stdout if no file_name supplied.
    -i, --import [FILE_NAME]         Import configuration from a file or stdin if no file_name supplied.
    -C, --copy SOURCE_PATH           Import configuration from a file or stdin if no file_name supplied.
    -D, --diff [FILE_NAME]           Compare configuration from a file or stdin if no file_name supplied.
    -c, --console                    Start interactive console.
    -p, --path PATH                  Path to import from / export to.
    -P, --provider PROVIDER          Provider to use. [ssm | file]. Default: ssm
    -U, --no-filter                  Do not filter passwords and keys.
    -d, --prune                      During import delete all existing keys for which there is no key in the import file.
    -k, --key_id KEY_ID              AWS KMS Key id or Key Alias to use when importing configuration values. Default: AWS Default key.
    -r, --region REGION              AWS Region to use. Default: AWS_REGION env var.
    -R, --random_size INTEGER        Size to use when generating random values. Whenever $random is encountered during an import. Default: 32
    -v, --version                    Display Symmetric Encryption version.
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

    secret_config --import production.yml --path /production/my_application

Import a yaml file, into a path in AWS SSM Parameter Store, using a custom KMS key to encrypt the values:

    secret_config --import production.yml --path /production/my_application --key_id "arn:aws:kms:us-east-1:23643632463:key/UUID"

#### Export SSM parameters

In AWS SSM Parameter store it can be difficult to 
Export the values from a specific path into a yaml or json file so that they are easier to read.

Export from a path in AWS SSM Parameter Store to a yaml file, where passwords are filtered:

    secret_config --export production.yml --path /production/my_application

Export from a path in AWS SSM Parameter Store to a yaml file, _without_ filtering out passwords:

    secret_config --export production.yml --path /production/my_application --no-filter

Export from a path in AWS SSM Parameter Store to a json file, where passwords are filtered:

    secret_config --export production.json --path /production/my_application

#### Copy values between paths in AWS SSM parameter store

It can be useful to keep a "master" copy of the values for an environment or stack in a custom path
in AWS Parameter Store. Then for each stack or environment that is spun up, copy the "master" / "common" values
into the new path. Once copied the values specific to that path can be updated accordingly.

Copy configuration from one path in AWS SSM Parameter Store to another path in AWS SSM Parameter Store:

    secret_config --copy /production/my_application --path /tenant73/my_application

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

Add to `application.rb`:

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
