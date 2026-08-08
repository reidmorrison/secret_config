---
layout: default
---

## Interpolation and Imports
{:.no_toc}

**Contents**

* TOC
{:toc}

Values are not always literal. Secret Config understands two kinds of markup inside the store:

* **`${...}` interpolation** substitutes something known only at runtime into a value: the host name,
  the date, an environment variable.
* **`__import__`** copies another subtree into a node, so that settings shared by several nodes are
  written once.

Both are evaluated when the registry is loaded and again on every `refresh!`, never when a key is read.
Reads stay in-memory hash lookups no matter how much markup a value contains.

Both can be turned off with `interpolate: false`. See [Configuration](config).

## Step 1: Substitute an environment variable

`${env:NAME}` reads an environment variable at load time:

~~~yaml
development:
  mysql:
    host: ${env:DB_HOST}
~~~

If `DB_HOST` is not set, loading raises `SecretConfig::MissingEnvironmentVariable`. Supply a fallback
after a comma to make it optional:

~~~yaml
development:
  mysql:
    host: ${env:DB_HOST,127.0.0.1}
~~~

The default is stripped of surrounding spaces, and cannot itself contain a comma.

This is not the same as the automatic
[environment variable override](api#step-6-override-with-an-environment-variable), which applies to
every key without being asked. `${env:...}` is explicit, names a variable that need not match the key,
and can be embedded in a larger string:

~~~yaml
development:
  mysql:
    host: ${env:DB_HOST,127.0.0.1}:3306
~~~

## Step 2: Substitute the host or process

~~~yaml
development:
  logger:
    file_name: /var/log/my_application_${hostname}.log
~~~

Each process now writes to a file named after the machine it is on, from one shared setting.

| Token | Value |
| --- | --- |
| `${hostname}` | Full host name |
| `${hostname:short}` | Host name up to the first period |
| `${pid}` | Process id |

`${pid}` gives every process on a host its own file:

~~~yaml
development:
  logger:
    file_name: /var/log/my_application_${hostname:short}_${pid}.log
~~~

## Step 3: Substitute the date or time

~~~yaml
development:
  logger:
    file_name: /var/log/my_application_${date}.log
    # => /var/log/my_application_20260808.log
~~~

| Token | Format |
| --- | --- |
| `${date}` | `%Y%m%d`, for example `20260808` |
| `${date:format}` | Any [strftime](https://docs.ruby-lang.org/en/master/strftime_formatting_rdoc.html) format |
| `${time}` | `%Y%m%d%H%M%S%L`, down to milliseconds |
| `${time:format}` | Any strftime format |

~~~yaml
development:
  logger:
    file_name: /var/log/my_application_${date:%Y-%m-%d}.log
    # => /var/log/my_application_2026-08-08.log
~~~

Note that these are evaluated at load time, not as the process runs. A process that starts before
midnight and runs for a week keeps the date it started with, until it is refreshed or restarted.

## Step 4: Substitute a random or selected value

`${random}` produces a URL-safe random value of 32 bytes. `${random:size}` sets the size:

~~~yaml
development:
  cache:
    namespace: my_application_${random:8}
~~~

The size must be a positive integer. Anything else, such as `${random:abc}`, raises
`SecretConfig::ConfigurationError` rather than quietly generating nothing.

`${select:a,b,c}` picks one of the supplied values:

~~~yaml
development:
  mongo:
    primary: ${select:mongo1.example.net,mongo2.example.net,mongo3.example.net}
~~~

Each process picks its own, which spreads a fleet across several servers without coordinating anything.
Values are separated by commas, are stripped of surrounding spaces, cannot contain a comma, and there
must be at least two of them.

**Both produce a new value on every restart and every refresh.** That makes them wrong for anything that
has to stay stable. A password written as `${random}` becomes a different password every time the
process starts, which is a locked-out application rather than a secure one.

For a value that must be generated once and then kept, use the command line's `__generate__` token,
which materializes the value during an import and writes it to the store. See
[Command Line](cli).

## Step 5: Escape a literal `${`

A value that should contain `${...}` literally is escaped by doubling the dollar sign:

~~~yaml
development:
  templates:
    greeting: $${name}, welcome back
    # => "${name}, welcome back"
~~~

Only `${` starts an interpolation. A bare `$`, or `$$` on its own, is left alone.

## Step 6: Share settings with `__import__`

A key named `__import__` copies the settings under another path into its parent node. It is useful when
several nodes share most of their settings and differ in only a few:

~~~yaml
test:
  my_application:
    mongo:
      database:  secret_config_test
      primary:   127.0.0.1:27017
      secondary: 127.0.0.1:27018

    mongo_reporting:
      __import__: mongo
      primary:    reporting.example.net:27017
~~~

`mongo_reporting` ends up with `database` and `secondary` copied from `mongo`, and keeps its own
`primary`. The `__import__` key itself is removed and never appears in the registry.

How imports resolve:

* **A relative value**, such as `mongo` above, is resolved against the root path of the registry, not
  against the node doing the importing.
* **An absolute value**, such as `/test/my_application/mongo`, is read from the provider directly, which
  allows one application to import settings from a path outside its own root. Each absolute import is a
  separate call to the provider, so they cost more than relative ones.
* **An existing key always wins** over an imported one, which is what makes the `primary` override
  above work.
* **A path that itself contains an `__import__` can be imported.** It is resolved first, so the settings
  it brings in are imported too, no matter which of the two nodes is declared first.
* **Imports must not form a cycle.** Two nodes that import each other, or a node that imports itself,
  raise `SecretConfig::ConfigurationError`, whether they refer to each other by relative or absolute
  path. The error message lists the cycle.
* **Imports are only applied when interpolation is enabled**, which is the default. The CLI leaves them
  in place on export unless `--interpolate` is supplied, which is what keeps an export re-importable.

The common use is a shared base path for a fleet of tenants, where each tenant imports the common
settings and overrides the handful that are its own.

## A setting that is both a value and a branch

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

## Reference

All interpolation tokens:

| Token | Result |
| --- | --- |
| `${date}` | Current date as `%Y%m%d` |
| `${date:format}` | Current date in the supplied strftime format |
| `${time}` | Current date and time as `%Y%m%d%H%M%S%L` |
| `${time:format}` | Current date and time in the supplied strftime format |
| `${env:name}` | The named environment variable. Raises `MissingEnvironmentVariable` when unset |
| `${env:name,default}` | The named environment variable, or `default` when unset |
| `${hostname}` | Full host name |
| `${hostname:short}` | Host name up to the first period |
| `${pid}` | Process id |
| `${random}` | URL-safe random value, 32 bytes |
| `${random:size}` | URL-safe random value of `size` bytes |
| `${select:a,b,c}` | One of the supplied values, chosen at random |
| `$${...}` | A literal `${...}`, not interpolated |

Reserved keys:

| Key | Meaning |
| --- | --- |
| `__import__` | Copy the settings at the given path into this node |
| `__value__` | The value belonging to a node that also has children |
| `__generate__` | Import-time random value. Handled by the [CLI](cli), not by interpolation |

## Next steps

* [Command Line](cli): `__generate__`, and how imports and exports treat this markup.
* [Guide](api): reading the resulting values.
* [Configuration](config): turning interpolation off.
