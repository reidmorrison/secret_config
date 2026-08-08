---
layout: default
---

## What is Secret Config?
{:.no_toc}

**Contents**

* TOC
{:toc}

Secret Config is centralized configuration and secrets management for Ruby and Rails applications.

It reads a tree of settings from one place, a local YAML file in development or AWS SSM Parameter Store
in production, into memory when the application starts, and serves them through a global `SecretConfig`
singleton:

~~~ruby
SecretConfig.fetch("mysql/host")
# => "db.example.net"

SecretConfig.fetch("mysql/pool_size", type: :integer, default: 5)
# => 25
~~~

Everything is read once at startup, so every lookup after that is an in-memory hash read. There is no
network call on the path that reads a setting.

## Why use it?

### The problem with configuration files

A typical Rails application spreads its settings across `database.yml`, `redis.yml`,
`symmetric-encryption.yml`, a handful of initializers, and a growing list of environment variables. The
production credentials live in some of those files, so they end up in one of three places: committed to
the repository, baked into the container image, or passed in as plain-text environment variables that
show up in `ps`, in crash reports, and in the container definition.

Adding a tenant, or a second production stack, means copying all of it and editing it by hand.

### The Secret Config way

Move the values out of the files and into a central store, addressed by a path:

~~~yaml
# What is left in database.yml
production:
  adapter:  mysql2
  encoding: utf8
  host:     <%= SecretConfig.fetch("mysql/host") %>
  database: <%= SecretConfig.fetch("mysql/database") %>
  username: <%= SecretConfig.fetch("mysql/username") %>
  password: <%= SecretConfig.fetch("mysql/password") %>
~~~

The file no longer holds a secret, and it no longer differs between environments. The value comes from
whatever store the application was pointed at, and the path it was pointed at is the only thing that
changes between development, production, and a per-tenant stack:

    /development/my_application
    /production/my_application
    /production/tenant73/my_application

The same container image now runs in every one of them.

## Quick start

This runs entirely from a local file. No AWS account is involved.

**Step 1.** Add the gem to your `Gemfile`:

~~~ruby
gem "secret_config"
~~~

**Step 2.** Create `config/application.yml`:

~~~yaml
development:
  mysql:
    host:     127.0.0.1
    database: my_application_development
    username: my_application
    password: secret

  logger:
    level:     info
    pool_size: 25
~~~

**Step 3.** Read the settings:

~~~ruby
require "secret_config"

SecretConfig.use(:file, path: "/development")

SecretConfig.fetch("mysql/host")
# => "127.0.0.1"

SecretConfig.fetch("logger/pool_size", type: :integer)
# => 25
~~~

**Step 4.** Override any setting with an environment variable, without touching the file. The name is the
key, upcased, with `/` replaced by `_`:

~~~shell
export MYSQL_HOST=db.example.net
~~~

~~~ruby
SecretConfig.fetch("mysql/host")
# => "db.example.net"
~~~

That is the whole model. Everything else builds on it.

In Rails, `SecretConfig.use` is replaced by a line in `application.rb` and the path defaults to the Rails
environment. See the [Rails guide](rails).

## Where settings are stored

| Store | Used for |
| --- | --- |
| A local YAML file | Development and test. Checked into source control, holds no production credentials. |
| AWS SSM Parameter Store | Production. Encrypted at rest with a KMS key you choose. |
| Environment variables | Overriding any single setting from either store, in any environment. |

Both stores are [providers](providers), and application code does not change between them. You can also
write your own.

## What you get

* **Secrets are encrypted at rest** in the Parameter Store, under a KMS key you choose, which can be
  rotated without touching the values.
* **Nothing sensitive is in the image or the repository.** A container needs one environment variable,
  `SECRET_CONFIG_PATH`, to know which configuration it is running.
* **Multi-tenancy is a path.** Spinning up a tenant is copying a subtree and changing the few values that
  differ, which the [command line tool](cli) does in one call.
* **Operations owns production configuration.** Host names, pool sizes and passwords can change without a
  developer, a deploy, or a code review.
* **It costs almost nothing.** Standard-tier parameters are free, and a custom KMS key is about $1 per
  month. AWS Secrets Manager charges per secret, which adds up quickly at the scale of an entire
  application's configuration. Confirm current
  [AWS SSM pricing](https://aws.amazon.com/systems-manager/pricing/) for your account, and see
  [Providers](providers) for the Parameter Store size and rate limits.

## Next steps

* [Getting Started](guide): install it, and convert an existing application.
* [Guide](api): the full programming interface, taught step by step.
* [Rails](rails): `application.rb` setup, `database.yml`, and containers.
* [Command Line](cli): import, export, diff, and per-tenant copies.
