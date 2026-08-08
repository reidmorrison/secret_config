---
layout: default
---

## Upgrading
{:.no_toc}

**Contents**

* TOC
{:toc}

This page covers what changes between major versions and what to do about it. The full record, including
every non-breaking change, is in
[CHANGELOG.md](https://github.com/reidmorrison/secret_config/blob/main/CHANGELOG.md).

Secret Config follows [Semantic Versioning](https://semver.org/). Breaking changes are confined to major
releases: within a minor or patch release the meaning of a key, the return type of a call, the default
value of an option, and the supported Ruby version all stay put.

## Upgrading to v2

v2 is where the accumulated breaking changes land. None of them require a change to how settings are
stored, so the store itself does not need to be migrated. The work is in application code.

### Ruby 3.2 is the minimum

The gemspec previously declared Ruby 2.3, but CI has only ever tested 3.2 and later. This makes the
supported version match what is actually tested.

### `key?` now consults environment variables

`key?` read the in-memory cache directly, which meant it disagreed with `[]` and `fetch`, both of which
have always honored an environment variable override. It now returns `true` for a key that is supplied
only by an environment variable, whenever `SecretConfig.check_env_var?` is true.

~~~shell
export MYSQL_REPLICA_HOST=replica.example.net
~~~

~~~ruby
SecretConfig.key?("mysql/replica_host")
# v1: false
# v2: true
~~~

**What to do:** code that used `key?` to ask specifically whether the *central store* holds a key gets a
different answer now. Set `SecretConfig.check_env_var = false` to restore the old meaning.

Most uses are unaffected, because most are asking "is a value available", which is what it now answers.

### Env-var-only keys are no longer cached

Reading a key that exists only as an environment variable used to write it into the in-memory copy.
That had two consequences: `key?` changed its answer partway through a process, and the key leaked into
`configuration` output once anything had read it.

The memoization is gone. Two things follow:

* A change to an environment variable that has **no matching key in the store** now takes effect on the
  next read, rather than being pinned to whatever was seen the first time.
* Such a key no longer appears in `SecretConfig.configuration`.

Overrides of keys that *are* in the store are still applied at load time, so those still need a
`refresh!` to pick up a change. That has not changed.

**What to do:** usually nothing. Code that relied on reading an env-var-only key to make it show up in
`configuration` needs another approach.

### `fetch` calls a block even without a `default:`

The missing-key check ran before the block was considered, so a block on its own raised
`MissingMandatoryKey` and was only ever reached when a `default:` was also supplied, which it then took
precedence over. The block is now called whenever the key is missing:

~~~ruby
SecretConfig.fetch("mysql/port") { 3306 }
# v1: raises MissingMandatoryKey
# v2: 3306
~~~

**What to do:** code that relies on `fetch(key) { ... }` raising must drop the block to keep raising.
This is worth grepping for, since v1 code would only have written a bare block by mistake.

### `$(random)` is renamed to `__generate__`

A single character separated `$(random)` from the `${random}` interpolation, and the two behave very
differently: `$(random)` is materialized once during a CLI import and persisted, whereas `${random}` is
re-evaluated on every startup and refresh. Confusing them produces an application whose password
changes on every restart.

~~~yaml
# Before
mysql:
  password: $(random)

# After
mysql:
  password: __generate__
~~~

`$(random)` still works in v2, but prints a deprecation warning on stderr and will be removed in the
next major release. It does not accept a per-key size.

### `--random_size` is deprecated

It set one size for every generated value in an import, so two keys needing different sizes meant two
separate imports. Supply the size on the value instead:

~~~yaml
mysql:
  password: __generate__        # 32 bytes
  api_key:  __generate__:64     # 64 bytes
~~~

The flag still works, and still sets the default for a bare `__generate__`, but warns when supplied.

### Silencing the deprecation warnings

While migrating, set `SECRET_CONFIG_SILENCE_DEPRECATIONS` to any value to suppress both warnings:

~~~shell
export SECRET_CONFIG_SILENCE_DEPRECATIONS=1
~~~

### New in v2

Not breaking, but worth adopting:

* **`secret-config --provider file`** works for every command except `--console`, so imports, exports and
  diffs can be run against a local YAML file with no AWS credentials. See [Command Line](cli).
* **`Providers::File` is writable.** `set` and `delete` work against a file, and a file no longer has to
  exist before it is used. See [Providers](providers).
* **`SECRET_CONFIG_FILE_NAME`** selects the file the file provider reads and writes, which previously
  could not be changed when the provider was selected by environment variable.
* **`interpolate:`** is accepted by `SecretConfig.use`, having previously been reachable only by
  constructing a `Registry` directly.
* **Circular `__import__` raises `ConfigurationError`** with the cycle in the message, rather than
  overflowing the stack, and an `__import__` of a node that is itself an import now resolves regardless
  of declaration order.

## Upgrading to v1.0

No breaking changes. v1.0.0 fixed the handling of a `nil` default on `fetch`.

## Upgrading to v0.10

### `${...}` replaces `%{...}`

String interpolation changed from `%` to `$`. Change every interpolated value **before** upgrading,
since the old form is not recognized afterwards:

~~~yaml
# Before
logger:
  file_name: /var/log/my_application_%{date}.log

# After
logger:
  file_name: /var/log/my_application_${date}.log
~~~

An export, a search and replace, and an import is the quickest way through it for a store of any size.
See [Command Line](cli).

## Upgrading to v0.9

### The command line program was renamed

`secret_config` became `secret-config`, with an underscore changed to a hyphen, and its arguments were
reworked to be consistent across operations. Any script or runbook calling the old name needs updating,
and the arguments should be checked rather than assumed:

    secret-config --help

## Next steps

* [Command Line](cli): the current CLI, including `__generate__`.
* [Guide](api): the current programming interface.
* [CHANGELOG.md](https://github.com/reidmorrison/secret_config/blob/main/CHANGELOG.md): the complete
  record.
