---
layout: default
---

## Configuration
{:.no_toc}

**Contents**

* TOC
{:toc}

This page covers everything that decides how the registry is built at startup: which provider it reads
from, what root path it reads under, and the environment variables that override both.

Rails applications configure this with one line in `application.rb`. See the [Rails guide](rails), which
covers setup there; the options themselves are all documented here.

## Step 1: Choose a provider and a path

~~~ruby
SecretConfig.use(:file, path: "/development")
~~~

Two arguments matter:

* **The provider**, `:file`, `:ssm` or `:secrets_manager`, decides where settings are read from. See
  [Providers](providers).
* **`path:`** is the root that every key is read relative to. It is absolute; a value given without a
  leading `/` has one added.

Anything else passed to `use` goes to the provider. `file_name:` for the file provider, `key_id:`,
`retry_count:` and the AWS client options for SSM, `key_id:` and `recovery_window_in_days:` for
Secrets Manager.

A typical non-Rails application picks the provider from its own environment:

~~~ruby
if ENV["APP_ENV"] == "production"
  SecretConfig.use(:ssm, path: "/production/my_application")
else
  SecretConfig.use(:file, path: "/development")
end
~~~

Call `use` as early as possible, before anything that reads a setting. The first call to any accessor
builds a default registry if `use` has not been called, and that default is rarely what you want.

## Step 2: Choose the root path

The root path uniquely identifies one configuration. Everything under it belongs to that instance of the
application, and nothing outside it is visible:

    /development/my_application
    /production/my_application

Two entirely separate production instances in one AWS account are two paths:

    /production1/my_application
    /production2/my_application

    /production/instance1/my_application
    /production/instance2/my_application

The shape is up to you. The only requirement is that it is unique within an AWS account. The same path
can be reused in a different account, and paths are not replicated across regions.

When no path is given, the registry falls back to `SECRET_CONFIG_PATH`, then `RAILS_ENV`, then
`Rails.env`. If none of those resolve, it raises `UndefinedRootError`.

## Step 3: Decide about environment variable overrides

Any key can be overridden by an environment variable named after it, upcased, with `/` replaced by `_`.
This is on by default:

~~~ruby
SecretConfig.check_env_var?
# => true
~~~

Turn it off to make the central store the only source:

~~~ruby
SecretConfig.check_env_var = false
~~~

It is worth turning off when the application runs somewhere that sets a lot of environment variables for
its own purposes, since key names like `logger/level` and `mysql/port` collide with common ones. Leaving
it on is the right default for most deployments, because it is the escape hatch that lets a setting be
changed without touching the store.

Overrides are covered in full, including exactly when a change takes effect, in
[Guide, Step 6](api#step-6-override-with-an-environment-variable).

## Step 4: Decide about interpolation

Values may contain `${...}` tokens, and a node may contain an `__import__` key. Both are evaluated when
the registry is loaded. This is on by default:

~~~ruby
SecretConfig.use(:ssm, path: "/production/my_application", interpolate: false)
~~~

Setting `interpolate: false` stores every value exactly as it appears, tokens and all, and leaves
`__import__` keys visible in the registry. It exists for tooling that needs to see the store verbatim.
Applications should leave it on. See [Interpolation](interpolation).

The other reason to turn it off is trust. `${env:NAME}` lets a setting read the process environment,
and an absolute `__import__` lets it read another path, so whoever may write to a path can reach both.
That is fine for a store your own team controls, which is the normal case. See
[Interpolation](interpolation#what-the-store-is-trusted-to-do) for what a setting can and cannot do.

## Step 5: Set the filters, if the defaults do not fit

Keys matching `SecretConfig.filters` have their values masked in `configuration` output and in command
line exports. The default list:

~~~ruby
SecretConfig.filters
# => [/password/i, /key\Z/i, /passphrase/i, /secret/i, /pwd\Z/i]
~~~

See [Guide, Step 11](api#step-11-keep-secrets-out-of-dumps).

## Environment variables

These are read at startup and change how the registry is built. They are the only configuration a
deployed container normally needs.

| Name | Effect | Precedence |
| --- | --- | --- |
| `SECRET_CONFIG_PATH` | Root path the configuration is read from | Wins over the configured `path:` |
| `SECRET_CONFIG_PROVIDER` | Provider to use, `file`, `ssm` or `secrets_manager` | Wins over the configured provider |
| `SECRET_CONFIG_FILE_NAME` | File the `file` provider reads and writes | Used when no `file_name:` is given |
| `SECRET_CONFIG_KEY_ID` | KMS key id used when writing to SSM or Secrets Manager | Used when no `key_id:` is given |
| `SECRET_CONFIG_KEY_ALIAS` | KMS key alias used when writing to SSM or Secrets Manager | Used when no `key_alias:` is given |
| `SECRET_CONFIG_SILENCE_DEPRECATIONS` | Suppresses deprecation warnings on stderr, when set to any value | n/a |

`SECRET_CONFIG_PATH` and `SECRET_CONFIG_PROVIDER` override what the code asked for, which is what makes
one image deployable everywhere:

~~~shell
export SECRET_CONFIG_PROVIDER=ssm
export SECRET_CONFIG_PATH=/production/my_application
~~~

The two KMS variables and `SECRET_CONFIG_FILE_NAME` work the other way round: an explicit argument in
code wins, and the variable supplies the value when there is none.

One consequence of `SECRET_CONFIG_PROVIDER` is worth knowing: when it selects a **different** provider
from the one the code asked for, the arguments passed alongside are dropped, since they were meant for
the other provider. Setting `SECRET_CONFIG_PROVIDER=file` against a `use(:ssm, path: ..., key_id: ...)`
gives a file provider with its own defaults, not a file provider carrying a `key_id`. Supply what it
needs through `SECRET_CONFIG_FILE_NAME` instead.

Note that these are distinct from the per-setting overrides in
[Guide, Step 6](api#step-6-override-with-an-environment-variable). These configure Secret Config itself;
those replace individual values.

## The registry

`SecretConfig.registry` returns the underlying `Registry`, which is occasionally useful for
diagnostics:

~~~ruby
SecretConfig.registry.path
# => "/development"

SecretConfig.registry.provider
# => #<SecretConfig::Providers::File:0x...>

SecretConfig.registry.interpolate
# => true
~~~

Calling `use` again replaces the registry entirely, which re-reads everything from the new provider.
That is how a test suite points at a different store; see [Testing](testing).

## Next steps

* [Providers](providers): the file and SSM providers, their options, and writing your own.
* [Rails](rails): where all of this goes in a Rails application.
* [Interpolation](interpolation): `${...}` and `__import__`.
