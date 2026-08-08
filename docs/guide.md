---
layout: default
---

## Getting Started
{:.no_toc}

**Contents**

* TOC
{:toc}

This page takes an existing application from no Secret Config at all to reading its first settings, and
then converts the configuration files it already has. It stays on the local file provider throughout, so
nothing here needs an AWS account.

Once this is working, the [Guide](api) covers the full programming interface, and
[Command Line](cli) covers moving the settings into AWS SSM Parameter Store for production.

## Step 1: Install

Add to your `Gemfile`:

~~~ruby
gem "secret_config"
~~~

Then:

    bundle install

Secret Config requires Ruby 3.2 or later. The AWS SDK is not a dependency, so nothing is installed for
Parameter Store until you ask for it. See [Providers](providers).

## Step 2: Create the development and test settings file

Create `config/application.yml`. This file holds the settings for local development and for the test
suite. It is shared by every developer on the team and is checked into source control:

~~~yaml
development:
  mysql:
    host:     127.0.0.1
    database: my_application_development
    username: my_application
    password: secret

  mongo:
    database:  my_application_development
    primary:   127.0.0.1:27017
    secondary: 127.0.0.1:27018

  secrets:
    secret_key_base: somereallylongstring

test:
  mysql:
    host:     127.0.0.1
    database: my_application_test
    username: my_application
    password: secret

  mongo:
    database:  my_application_test
    primary:   127.0.0.1:27017
    secondary: 127.0.0.1:27018

  secrets:
    secret_key_base: somereallylongteststring
~~~

The top level keys are environments. Everything under one of them is that environment's settings, grouped
into a hierarchy that can go as deep as you like.

**Do not put production credentials in this file.** Those belong in the central store, which is what the
rest of the documentation is about. This file is for values that are safe for every developer to have,
and safe to commit.

## Step 3: Point the application at it

~~~ruby
require "secret_config"

SecretConfig.use(:file, path: "/development")
~~~

`path` is the root that everything is read relative to. Because it is `/development` here, the key
`mysql/host` resolves to `development.mysql.host` in the file above.

Rails applications do this differently, with one line in `application.rb` that also picks the path from
`Rails.env`. See the [Rails guide](rails).

## Step 4: Read a setting

~~~ruby
SecretConfig.fetch("mysql/host")
# => "127.0.0.1"
~~~

Keys are paths into the tree, joined with `/`, and they are relative to the root set in Step 3.

That is enough to start. The [Guide](api) picks up here and covers type conversion, defaults, lists,
binary values, and the rest.

## Step 5: Convert an existing config file

Now go through the configuration files the application already has, and look for the values that differ
between environments or that should not be committed.

A typical `database.yml` before:

~~~yaml
defaults: &defaults
  encoding: utf8
  adapter:  mysql2

development:
  <<:       *defaults
  database: my_application_development
  username: jack
  password: jackrules
  host:     localhost

test:
  <<:       *defaults
  database: my_application_test
  username: tester
  password: khjsdjhdsjhdsr32
  host:     test.server

production:
  <<:       *defaults
  database: my_application_production
  username: product
  password: donotexpose45
  host:     production.server
~~~

Replace the values with calls to `SecretConfig.fetch`:

~~~yaml
configuration: &configuration
  encoding: utf8
  adapter:  mysql2
  database: <%= SecretConfig.fetch("mysql/database") %>
  username: <%= SecretConfig.fetch("mysql/username") %>
  password: <%= SecretConfig.fetch("mysql/password") %>
  host:     <%= SecretConfig.fetch("mysql/host") %>

development:
  <<: *configuration

test:
  <<: *configuration

production:
  <<: *configuration
~~~

The three environments are now identical, because the thing that differed between them has moved out. The
production password is no longer in the repository, and adding a fourth environment does not mean editing
this file at all.

Repeat for `redis.yml`, `symmetric-encryption.yml`, and any initializer holding a credential. There are
worked examples for a few common ones on the [Rails](rails) page.

## Step 6: Replace custom config files in libraries

The same idea removes proprietary config files from gems and internal libraries. Instead of requiring a
config file of its own, a library reads what it needs directly:

~~~ruby
def http_client
  @http_client ||=
    PersistentHTTP.new(
      name:         "HTTPClient",
      url:          SecretConfig.fetch("http_client/url"),
      logger:       logger,
      pool_size:    SecretConfig.fetch("http_client/pool_size", type: :integer, default: 10),
      warn_timeout: SecretConfig.fetch("http_client/warn_timeout", type: :float, default: 0.25),
      open_timeout: SecretConfig.fetch("http_client/open_timeout", type: :float, default: 30),
      read_timeout: SecretConfig.fetch("http_client/read_timeout", type: :float, default: 30),
      force_retry:  true
    )
end
~~~

An application using that library adds only the entries it wants to change:

~~~yaml
http_client:
  url:          https://test.example.com
  pool_size:    20
  read_timeout: 300
~~~

No custom config file, no initializer, and the values can still be overridden per environment or per
tenant later without the library knowing.

When a library reads several settings under one path, `SecretConfig.configure` names that path once
instead of repeating it. See [Naming a subtree once](api#step-9-name-a-subtree-once) in the Guide.

## Next steps

* [Guide](api): the full programming interface.
* [Configuration](config): `SecretConfig.use` options and the environment variables that change startup.
* [Rails](rails): `application.rb`, containers, and worked examples.
* [Command Line](cli): moving these settings into AWS SSM Parameter Store.
