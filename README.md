# Secret Config
[![Gem Version](https://img.shields.io/gem/v/secret_config.svg)](https://rubygems.org/gems/secret_config) [![Build Status](https://travis-ci.org/rocketjob/secret_config.svg?branch=master)](https://travis-ci.org/rocketjob/secret_config) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Beta-yellow.svg) [![Gitter chat](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Centralized Configuration and Secrets Management for Ruby and Rails applications.

Securely store configuration information centrally.

## Project Status

Early development.

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

### Usage

Go through all the configuration files and look for sensitive data such as passwords:

Example `database.yml`:

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
