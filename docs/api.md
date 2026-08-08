---
layout: default
---

## Guide
{:.no_toc}

**Contents**

* TOC
{:toc}

This page walks the whole programming interface, one step at a time. Each step builds on the one before
it, using a single example application whose configuration grows as it goes.

If you have not installed the gem yet, start with [Getting Started](guide).

Throughout, the application is pointed at a local file:

~~~ruby
require "secret_config"

SecretConfig.use(:file, path: "/development")
~~~

Nothing on this page changes when that becomes AWS SSM Parameter Store in production. That is the point
of it: the code reads keys, and where the values come from is a deployment decision. See
[Configuration](config) and [Providers](providers).

## Step 1: Read a value

Start with two settings in `config/application.yml`:

~~~yaml
development:
  mysql:
    host:     127.0.0.1
    database: my_application_development
~~~

`fetch` returns the value for a key, and raises when the key is missing:

~~~ruby
SecretConfig.fetch("mysql/host")
# => "127.0.0.1"

SecretConfig.fetch("mysql/port")
# => SecretConfig::MissingMandatoryKey (Missing configuration value for /development/mysql/port)
~~~

`[]` does the same thing but returns `nil` instead of raising:

~~~ruby
SecretConfig["mysql/host"]
# => "127.0.0.1"

SecretConfig["mysql/port"]
# => nil
~~~

Prefer `fetch`. A missing setting is nearly always a deployment mistake, and it is much easier to
diagnose from an exception naming the key at startup than from a `nil` that surfaces three layers away.

Keys are relative to the root path set in `use`, so `mysql/host` above reads `/development/mysql/host`.

## Step 2: Supply a default

Not every setting has to be present. Give `fetch` a `default:` for the ones that do not:

~~~ruby
SecretConfig.fetch("mysql/port", default: 3306)
# => 3306
~~~

When the default is expensive to compute, or is only valid when the key really is absent, pass a block
instead. It is called only when the key is missing:

~~~ruby
SecretConfig.fetch("mysql/port") { discover_port_from_service_registry }
~~~

A block takes precedence over `default:` when both are supplied.

Use defaults for values with a sensible fallback, such as a pool size or a timeout. Do not use them for
credentials or host names: a default password that silently works in production is worse than a failure
at startup.

## Step 3: Convert the type

Values arrive as strings, because that is all AWS SSM Parameter Store and environment variables can
hold. `type:` converts them:

~~~yaml
development:
  mysql:
    host:      127.0.0.1
    database:  my_application_development
    pool_size: 25
    timeout:   0.5
    reconnect: true
    adapter:   mysql2
~~~

~~~ruby
SecretConfig.fetch("mysql/pool_size", type: :integer)
# => 25

SecretConfig.fetch("mysql/timeout", type: :float)
# => 0.5

SecretConfig.fetch("mysql/reconnect", type: :boolean)
# => true

SecretConfig.fetch("mysql/adapter", type: :symbol)
# => :mysql2
~~~

The supported types are `:string` (the default), `:integer`, `:float`, `:boolean`, `:symbol` and
`:json`. `:json` parses the value and returns the resulting Hash or Array.

Without `type:`, the value comes back as it was stored:

~~~ruby
SecretConfig.fetch("mysql/pool_size")
# => "25"
~~~

Type conversion is applied to a `default:` as well, so `default: 3306` and `default: "3306"` both come
back as `3306` under `type: :integer`.

## Step 4: Read a list

There is no array type. A list is one value with a delimiter, and `separator:` splits it:

~~~yaml
development:
  address_service:
    hostnames: primary.example.net,secondary.example.net,backup.example.net
    ports:     12345,5343,26815
~~~

~~~ruby
SecretConfig.fetch("address_service/hostnames", separator: ",")
# => ["primary.example.net", "secondary.example.net", "backup.example.net"]
~~~

`separator:` combines with `type:`, which is then applied to each element:

~~~ruby
SecretConfig.fetch("address_service/ports", type: :integer, separator: ",")
# => [12345, 5343, 26815]
~~~

Elements are stripped of surrounding whitespace, so `a, b, c` and `a,b,c` give the same result.

## Step 5: Read binary data

Encryption keys and initialization vectors are not text. Store them with strict base64 encoding, and
pass `encoding: :base64` to decode them on the way out:

~~~yaml
development:
  symmetric_encryption:
    iv: FW+/wLubAYM+ZU0bWQj59Q==
~~~

~~~ruby
# As stored:
SecretConfig.fetch("symmetric_encryption/iv")
# => "FW+/wLubAYM+ZU0bWQj59Q=="

# Decoded:
SecretConfig.fetch("symmetric_encryption/iv", encoding: :base64)
# => "\x15o\xBF\xC0\xBB\x9B\x01\x83>eM\eY\b\xF9\xF5"
~~~

Decoding happens before type conversion, so `encoding:` and `type:` can be combined.

## Step 6: Override with an environment variable

Any setting can be overridden by an environment variable, in any environment, without changing the
store. The name is the key, upcased, with `/` replaced by `_`:

| Key | Environment variable |
| --- | --- |
| `mysql/host` | `MYSQL_HOST` |
| `mysql/pool_size` | `MYSQL_POOL_SIZE` |
| `symmetric_encryption/iv` | `SYMMETRIC_ENCRYPTION_IV` |

~~~shell
export MYSQL_HOST=db.example.net
~~~

~~~ruby
SecretConfig.fetch("mysql/host")
# => "db.example.net"
~~~

This is how a developer points at a different database for an afternoon, and how a container is nudged
without editing the central store.

Two details are worth knowing:

* An override of a key that **exists in the store** is applied when the registry is loaded, so changing
  the variable inside a running process has no effect until the next
  [refresh](#step-10-refresh-at-runtime).
* A variable with **no matching key in the store** is read on every lookup, so a change to it takes
  effect on the next read. Such a key is never written into the in-memory copy, so it does not appear in
  `configuration` output.

Set `SecretConfig.check_env_var = false` to turn overrides off entirely. See
[Configuration](config) for when that is worth doing.

## Step 7: Ask whether a key is set

~~~ruby
SecretConfig.key?("mysql/host")
# => true
~~~

`key?` answers "is a value available", not "is this in the central store". A key supplied only by an
environment variable counts as present, so that `key?` agrees with `[]` and `fetch`, which both return
the override:

~~~ruby
SecretConfig.key?("mysql/replica_host")
# => false
~~~

~~~shell
export MYSQL_REPLICA_HOST=replica.example.net
~~~

~~~ruby
SecretConfig.key?("mysql/replica_host")
# => true
~~~

To ask about the central store alone, set `SecretConfig.check_env_var = false`.

`key?` is most useful for optional features: a secondary encryption key during a rotation, a replica
that only some deployments have.

## Step 8: Look at the whole tree

`configuration` returns a nested Hash copy of everything in the registry:

~~~ruby
SecretConfig.configuration
# => {
#      "mysql" => {
#        "host"      => "127.0.0.1",
#        "database"  => "my_application_development",
#        "pool_size" => 25,
#        "password"  => "[FILTERED]"
#      },
#      "logger" => {
#        "level" => "info"
#      }
#    }
~~~

Note the password. Values whose key looks sensitive are masked, which is covered in
[Step 11](#step-11-keep-secrets-out-of-dumps).

This is a debugging and diagnostics tool, for a console or a startup banner. It builds a new Hash every
time it is called, so it does not belong on a request path. Read individual keys with `fetch`.

## Step 9: Name a subtree once

When a component reads several settings under one path, repeating that path gets noisy:

~~~ruby
Kafka::Client.new(
  seed_brokers:       SecretConfig.fetch("suppliers/kafka_service/brokers", separator: ","),
  delivery_interval:  SecretConfig.fetch("suppliers/kafka_service/delivery_interval", type: :integer, default: 0),
  delivery_threshold: SecretConfig.fetch("suppliers/kafka_service/delivery_threshold", type: :integer, default: 0),
  max_queue_size:     SecretConfig.fetch("suppliers/kafka_service/max_queue_size", type: :integer, default: 10_000)
)
~~~

`SecretConfig.configure` takes the path once and yields an object that reads relative to it:

~~~ruby
SecretConfig.configure("suppliers/kafka_service") do |config|
  Kafka::Client.new(
    seed_brokers:       config.fetch("brokers", separator: ","),
    delivery_interval:  config.fetch("delivery_interval", type: :integer, default: 0),
    delivery_threshold: config.fetch("delivery_threshold", type: :integer, default: 0),
    max_queue_size:     config.fetch("max_queue_size", type: :integer, default: 10_000)
  )
end
~~~

The yielded object supports `fetch`, `[]`, `[]=`, `key?`, `set`, `delete`, `configuration` and
`refresh!`, with the same options as the global calls.

This is particularly useful in a library, which can take its root path as an argument and let the
application decide where its settings live.

## Step 10: Refresh at runtime

The registry is read once at startup. `refresh!` re-reads the whole tree from the provider:

~~~ruby
SecretConfig.refresh!
# => true
~~~

Keys that disappeared from the central store are dropped, changed values are picked up, and any
`${...}` [interpolation](interpolation) is evaluated again.

The usual way to trigger it in a long-running process is a signal. Add this on startup:

~~~ruby
Signal.trap("USR2") do
  SecretConfig.refresh!
end
~~~

Then, to make a running process re-read its configuration:

~~~shell
kill -SIGUSR2 1234
~~~

Where `1234` is the process ID. An event from a message queue, or a periodic timer, works equally well.

Because a refresh can change values underneath the application, read settings where they are used rather
than copying them into a constant at startup:

~~~ruby
# Picks up a refresh:
def pool_size
  SecretConfig.fetch("mysql/pool_size", type: :integer)
end

# Frozen at startup, ignores every refresh:
POOL_SIZE = SecretConfig.fetch("mysql/pool_size", type: :integer)
~~~

Lookups are in-memory hash reads, so calling `fetch` on every use is not a performance concern.

## Step 11: Keep secrets out of dumps

`SecretConfig.filters` holds a list of patterns. A key matching one of them has its value replaced with
`[FILTERED]` in `configuration` output and in command line exports:

~~~ruby
SecretConfig.filters
# => [/password/i, /key\Z/i, /passphrase/i, /secret/i, /pwd\Z/i]
~~~

They are matched against the relative key, case-insensitively, so `mysql/password` and
`SYMMETRIC_ENCRYPTION/Key` are both masked. Replace the list to suit your naming:

~~~ruby
SecretConfig.filters = [/password/i, /secret/i, /_token\Z/i, /api_key/i]
~~~

Set it to `nil` to disable masking entirely.

Filtering applies **only** to those dumps. `fetch` and `[]` always return the real value, so masking a
key never breaks the application that reads it. It exists so that a console session, a diagnostic page,
or an exported YAML file does not casually spill credentials.

## Step 12: Write a value

Settings can be written back to the store:

~~~ruby
SecretConfig["logger/level"] = "debug"

# Same thing:
SecretConfig.set("logger/level", "debug")
~~~

And removed:

~~~ruby
SecretConfig.delete("logger/level")
~~~

Both the file and the SSM providers support writing. Writing to a file rewrites it from its parsed
contents, so comments and formatting are lost. See [Providers](providers) before doing that to a file
you care about.

Most applications never write. Configuration is normally managed from the [command line](cli), by
whoever operates the environment, and only read by the application. Writing from application code is for
the rare case of a value the application itself generates.

## Troubleshooting

### `MissingMandatoryKey` at startup

The key is not in the store under the root path, and no `default:` was supplied. Check the root path
first, since it is the more common mistake:

~~~ruby
SecretConfig.registry.path
# => "/development"

SecretConfig.configuration.keys
# => ["mysql", "logger"]
~~~

The exception message contains the full path that was looked up, which makes the root path visible:
`Missing configuration value for /development/mysql/port`.

### A setting has the wrong value, and the store looks right

An environment variable is almost certainly overriding it. Check the name the key maps to:

~~~shell
env | grep MYSQL_
~~~

This is easy to hit by accident, because the names are short and generic. `PORT`, `HOST` and `LOG_LEVEL`
are set by many platforms for their own reasons.

### A value changed in the store but the application still sees the old one

The registry is read at startup. Call `SecretConfig.refresh!`, or restart. See
[Step 10](#step-10-refresh-at-runtime).

### `${random}` gives a different value on every restart

That is what it does. It is re-evaluated on every load and refresh, which makes it wrong for anything
that has to stay stable, such as a password. Use the command line's `__generate__` instead, which
materializes the value once during an import. See [Command Line](cli).

### An export shows `[FILTERED]` where a value should be

Working as intended. Pass `--no-filter` to the export, or adjust `SecretConfig.filters`. See
[Step 11](#step-11-keep-secrets-out-of-dumps).

### `UndefinedRootError: Either set env var 'SECRET_CONFIG_PATH' or call SecretConfig.use`

No root path was resolved. Outside Rails there is nothing to fall back on, so pass `path:` to
`SecretConfig.use`, or set `SECRET_CONFIG_PATH`. See [Configuration](config).

## Next steps

* [Configuration](config): `SecretConfig.use` options, and the environment variables that change startup.
* [Interpolation](interpolation): `${...}` values, `__import__`, and sharing settings between nodes.
* [Command Line](cli): managing the central store.
* [Testing](testing): controlling settings from a test suite.
