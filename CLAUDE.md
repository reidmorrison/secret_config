# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`secret_config` is a Ruby gem for centralized configuration and secrets management. It reads a tree of
key/value settings from a provider (AWS SSM Parameter Store, AWS Secrets Manager, or a local YAML
file), flattens it into an in-memory cache at startup, and serves it through a global `SecretConfig`
singleton. It ships a `secret-config` CLI for importing, exporting, diffing, and editing the central
store.

Docs source lives in [docs/](docs/) (Jekyll site published to https://config.reidmorrison.com/).

There are no known issues or open design questions outstanding. The `TECH_DEBT.md` that tracked them is
gone, having been worked through; [CHANGELOG.md](CHANGELOG.md) carries what came of each item. If a review
turns up something that is not being fixed now, raise it rather than leaving it undocumented.

## Git workflow

Never commit directly to `main`. Create a feature branch first, commit there, and open a pull request.
This applies to documentation and config changes too, not just code. If asked to commit while `main` is
checked out, branch first, then commit.

## Versioning and backward compatibility

This project follows [Semantic Versioning](https://semver.org/). Backward compatibility is a priority:
strive to preserve existing behavior, and confine breaking changes to major releases. Within a minor or
patch release, do not change the meaning of an existing key, the return type of an existing call, the
default value of an existing option, or the supported Ruby floor.

When a fix would change observable behavior, say so explicitly and let the maintainer decide whether it
waits for the next major release rather than folding it in silently.

The current version is 1.0.0. **A v2 release is planned to carry the unreleased changes in
[CHANGELOG.md](CHANGELOG.md)**, several of which are deliberately breaking. Target that work at v2 rather
than shipping it in a 1.x release.

## Commands

    bundle exec rake                                     # Default task: tests, then rubocop
    bundle exec rake test                                # Tests only
    bundle exec rake test TEST=test/registry_test.rb     # Run one test file
    bundle exec rake test TEST=test/registry_test.rb TESTOPTS="-n/filters/"    # Run tests matching a name
                                                         # note: no space after -n, rake's test loader
                                                         # otherwise treats the pattern as a filename
    bundle exec ruby -Ilib test/registry_test.rb         # Run one file directly

    bundle exec bin/secret-config --help                 # CLI usage

    bundle exec rubocop                                  # Lint
    bundle exec rubocop -a                               # Safe autocorrect
    bundle exec rubocop -A                               # Include unsafe autocorrect, review the diff

    bundle exec solargraph scan                          # Type-index the workspace, report load errors
    bundle exec solargraph typecheck lib/secret_config/registry.rb   # Type check one file
    bundle exec solargraph stdio                         # Language server, for editor integration

    rake gem                                             # Build the gem
    rake publish                                         # Tag, push, and push the gem to rubygems (maintainer only)

Tests are Minitest with the `describe`/`it` spec DSL nested inside `Minitest::Test` subclasses, run with
`-w` (warnings on) via the Rake test task. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) has
two jobs: `lint` runs `bundle exec rubocop` once on Ruby 3.4, and `test` runs `bundle exec rake test`
across Ruby 3.2, 3.3, 3.4, and 4.0. The test job calls `rake test` rather than the default task so that
rubocop is not repeated on every matrix entry; `TargetRubyVersion` decides which cops apply, so the lint
result does not depend on the Ruby it runs on.

SimpleCov runs on every test run and writes `coverage/index.html` (gitignored). No minimum threshold is
enforced, so coverage cannot fail the build. `cover "lib/**/*.rb"` is set deliberately: the `cli/` files and
`railtie.rb` are autoloaded, and without it they are omitted from the report rather than counted as
uncovered, which inflates the total. (`cover` replaced the equivalent `track_files`, which SimpleCov now
deprecates. The reported totals were identical either way.)

The baseline is 98.33% line / 91.31% branch. Every file is at 100% except `cli.rb` (94.5%, the uncovered
parts are `--console` and the two AWS branches of `#provider_instance`, none of which runs without AWS
credentials or `irb`), `providers/file.rb` (98.7%, the uncovered line is a Psych 3 fallback),
`providers/ssm.rb` (97.3%) and `providers/secrets_manager.rb` (97.6%), whose uncovered line in each case
is the `LoadError` rescue for the missing AWS SDK gem.
`railtie.rb` and `version.rb` report 0% for structural reasons: the railtie is only loaded under Rails, and
the gemspec loads `version.rb` before SimpleCov starts.

Measure the baseline with a cleared `coverage/` directory. SimpleCov merges resultsets from separate
suites within a timeout window, so a stray `ruby -Itest` run leaves stale data behind that skews the next
`rake test` figure in either direction.

Solargraph is configured by [.solargraph.yml](.solargraph.yml). It indexes `lib/` and `test/` and excludes
the Jekyll docs, and reports rubocop diagnostics through the language server.

Rubocop is bundled, with `rubocop-minitest` and `rubocop-rake` loaded as plugins in
[.rubocop.yml](.rubocop.yml). It runs as the second half of the default rake task and as its own CI job.
The style it encodes: double-quoted strings, trailing dot position, table-aligned hashes and assignments,
128-character lines.

Rubocop reports no offenses. Keep it that way rather than accumulating a backlog. No cop is excluded for a
file that cannot be brought into line; the one deliberate suppression is documented in place:

- `Naming/PredicateMethod` is disabled inline on `Registry#refresh!`, which returns `true` but cannot be
  renamed because it is public API delegated from `SecretConfig.refresh!`.

## Architecture

### Load path

`SecretConfig.use(provider, path:, **args)` (or the first call to any accessor, which lazily builds a default
registry) creates a `Registry`. `Registry#refresh!` walks the provider, feeds every key/value pair through a
`Parser`, and stores the result in a `Concurrent::Map`. Everything is read eagerly at startup, so runtime
lookups are pure in-memory hash reads. `refresh!` re-reads the whole tree and drops keys that disappeared
from the central store.

    SecretConfig (singleton facade, forwards to registry)
      └── Registry            flat Concurrent::Map cache, type conversion, env-var override, filtering
            ├── Parser        absolute → relative keys, ${...} interpolation, __import__ expansion
            │     └── SettingInterpolator < StringInterpolator
            └── Providers::{File,Ssm,SecretsManager} < Providers::Provider

### Key model

Providers yield **absolute** keys (`/test/my_application/mysql/host`). The `Parser` strips the registry's
root `path` so the cache is keyed by **relative** keys (`mysql/host`). Public API takes relative keys;
`Registry#expand_key` re-adds the root for writes. Anything starting with `/` is treated as absolute.

`Utils` converts between the flat cache and the nested hash returned by `configuration`. When a node is both
a value and a branch, its own value is stored under `NODE_KEY` (`"__value__"`) inside the branch hash.

### Interpolation and imports

Interpolation runs once, at load/refresh time, inside `Parser#parse`, so `${random}` and `${select:...}`
produce new values on every process restart or `refresh!`, not on every read. `SettingInterpolator` methods
(`date`, `time`, `env`, `hostname`, `pid`, `random`, `select`) are dispatched by name from
`StringInterpolator#parse`; adding a public method to `SettingInterpolator` adds a new `${name:args}` token,
so do not add public helper methods there casually. `$${...}` escapes interpolation.

A key named `__import__` copies another subtree into its parent node. A relative import value is resolved
against the already-parsed tree; an absolute one triggers a second provider fetch. Existing keys always win
over imported ones. An imported subtree may itself contain imports: those are resolved first, in either
declaration order.

Cycles raise `ConfigurationError`, guarded in two places, since the two kinds of import recurse through
different code. `Parser#apply_import` carries a `chain` of the import keys it is resolving, which covers
relative imports within one parser. Absolute imports leave the parser entirely, so `Registry#fetch_path`
threads a `fetch_chain` of the paths already being fetched into each `Parser` it builds, and
`Parser#fetch_absolute` raises when a path recurs. Match paths exactly there: a path nested under one
already being fetched is an ordinary import, not a cycle.

### Value handling

All values are stored and returned as strings. `fetch` applies, in order: env-var override, `encoding:`
(`:base64`), then `type:` (`:string`, `:integer`, `:float`, `:boolean`, `:symbol`, `:json`), with `separator:`
splitting into an array of converted elements. Missing keys raise `MissingMandatoryKey` unless `default:` or
a block is supplied.

Environment variables override the central store when `SecretConfig.check_env_var?` is true (the default).
The name is the relative key upcased with `/` replaced by `_`: `mysql/host` → `MYSQL_HOST`. Overrides of
keys that exist in the store are applied once, in `refresh!`. A key that exists only as an environment
variable is resolved on every read instead, and is never written into the cache, so `key?`, `[]`, and
`fetch` agree about it and `configuration` never reports it.

`SecretConfig.filters` (default: regexes matching password/key/passphrase/secret/pwd) mask values as
`[FILTERED]` in `configuration` output and CLI exports. Filtering applies only to those dumps, never to
`[]`/`fetch`.

### Environment variables that change startup behavior

`SECRET_CONFIG_PATH` overrides the configured root path; `SECRET_CONFIG_PROVIDER` overrides the provider
(defaults to `file`); `SECRET_CONFIG_FILE_NAME` sets the file the `file` provider reads and writes
(defaults to `config/application.yml`, and an explicit `file_name:` wins); `SECRET_CONFIG_KEY_ID` /
`SECRET_CONFIG_KEY_ALIAS` select the KMS key for the SSM provider. Absent an explicit path, the registry
falls back to `RAILS_ENV` then `Rails.env`.

### CLI

The CLI talks to a provider directly rather than through the global registry, so it can operate on any path
without `SECRET_CONFIG_PATH` being set. `CLI#provider_instance` builds `:ssm` and `:file`, and raises
`ArgumentError` for anything else. Exports filter secrets by default (`--no-filter` to disable) and leave
`${...}` uninterpolated unless `--interpolate` is passed, which keeps round-tripping an export back through
`--import` non-destructive.

    CLI                 dispatch, and the reporting that goes with each command
      ├── Options       the OptionParser and the options it sets; CLI delegates a reader for each
      ├── ConfigFile    the YAML or JSON file --export/--import/--diff transfer to or from
      ├── Differ        renders the difference between two flat hashes
      └── Importer      writes a config tree through the provider, resolving __generate__ tokens

Each lives in [lib/secret_config/cli/](lib/secret_config/cli/) and is autoloaded from `CLI`. Adding an
option means adding it to one of `Options`' `define_*_options` methods and to the `def_delegators` list in
[cli.rb](lib/secret_config/cli.rb). `Importer` is handed the current values rather than reading them, so
that a provider is all it needs; `CLI#current_values` is what supplies them, and what turns a store that
does not exist yet into an empty one.

Two file options that are easily confused: `--file` is what `--export`/`--import`/`--diff` transfer to or
from, while `--provider-file` is the store that `--provider file` reads and writes. `--provider file` makes
every command except `--console` runnable without AWS credentials, which is what most of the CLI test
coverage now relies on.

### Adding a provider

Subclass `Providers::Provider` and implement `each(path)` (yielding absolute key/value pairs), `set`,
`delete`, and `fetch`. Register it in the `autoload` list in [lib/secret_config.rb](lib/secret_config.rb);
`Utils.constantize_symbol` resolves `:my_provider` to `SecretConfig::Providers::MyProvider`. Optional
backends require their gem inside a `begin/rescue LoadError` that re-raises with an install hint, as
[providers/ssm.rb](lib/secret_config/providers/ssm.rb) does.

## Tests

Fixtures live in [test/config/application.yml](test/config/application.yml), which exercises interpolation,
`__import__`, node-plus-branch values, and comma-separated lists. Registry tests build a
`Providers::File` against that file with path `/test/my_application` or `/test/other_application`.
[test/config/imports.yml](test/config/imports.yml) holds the `__import__` resolution-order and cycle
fixtures. Each root in it is read on its own, so the deliberately invalid roots there (`circular`,
`self_referencing`, `absolute_a`/`absolute_b`, `absolute_self`) do not affect the valid ones.

`InMemoryProvider` in [test/test_helper.rb](test/test_helper.rb) is a writable provider that keeps the flat
key/value hash in memory, which is convenient when a test wants to assert on exactly what was written.
`Providers::File` is also writable now, so tests that need a real round trip copy the fixture into a
`Dir.mktmpdir` and point `--provider-file` at the copy rather than mutating `test/config/application.yml`.

[test/cli_test.rb](test/cli_test.rb) covers option parsing and drives each command end to end against the
file provider. [test/cli/importer_test.rb](test/cli/importer_test.rb) covers `CLI::Importer` on its own,
against an `InMemoryProvider`, since deciding what to write is where the behavior worth pinning down is.

There are two SSM test files. [test/providers/ssm_stubbed_test.rb](test/providers/ssm_stubbed_test.rb)
passes `stub_responses: true` and `region:` through `Ssm#initialize` into `Aws::SSM::Client`, so it never
touches AWS and runs everywhere; use it for new SSM coverage.
[test/providers/ssm_test.rb](test/providers/ssm_test.rb) does a live round trip and skips unless
`AWS_ACCESS_KEY_ID` is set, which is the source of the suite's 2 skips.

[test/providers/secrets_manager_stubbed_test.rb](test/providers/secrets_manager_stubbed_test.rb) covers
the Secrets Manager provider the same stubbed way, and has no live counterpart on purpose: every secret
a round trip created would be billed for a month and could not be deleted outright, since that provider
deliberately does not offer `ForceDeleteWithoutRecovery`.

A test that deliberately asserts current, undesired behavior carries a comment saying so, and says what
the desired behavior is; update it when fixing the underlying issue rather than treating a failure there
as a regression. There are none at present.

[test/test_helper.rb](test/test_helper.rb) requires `cgi/escape` before `amazing_print` on purpose: Ruby 4.0
removed `cgi` from stdlib and the shim warns if loaded reentrantly. Keep that require first.
