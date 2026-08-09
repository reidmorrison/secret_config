# Changelog

All notable changes to this project are documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/). Entries for releases up to and
including v1.0.0 were reconstructed from the git history and are summaries rather than exhaustive lists.

## Unreleased

Targeted at v2, since it carries breaking changes.

### Security

- **A value in the central store can no longer run arbitrary code when the configuration is loaded.**
  `${...}` dispatch was guarded by `respond_to?`, which is true for every method an object inherits, so
  a value of `${send:eval,...}` or `${send:system,...}` reached `Object#send` and through it any method
  at all. Anything able to write a single setting, an SSM parameter, a Secrets Manager secret, a
  `config/application.yml`, or a file passed to `--import`, could therefore run code in every process
  that loaded that path, at startup, before the application itself ran. Dispatch now goes through an
  explicit list of declared interpolations. Every documented token is unchanged. A subclass of
  `StringInterpolator` or `SettingInterpolator` that added a token by defining a public method must now
  also declare it with `interpolation :name`; see
  [Interpolation](https://config.reidmorrison.com/interpolation.html).
- **Files written by the file provider and by `--export` are created readable only by their owner.**
  Both wrote through `::File.write`, which applies the umask, creating world-readable files that hold
  settings, and secrets in the case of `--export --no-filter`, in the clear. New files are created with
  mode `0600`. A file that already exists keeps its mode, since it may have been widened deliberately,
  and a warning naming it is printed instead.
- **`--diff` masks secrets by default**, the way `--export` already did, with `--no-filter` to see them.
  A diff is what you run to check a change before importing it, frequently in a terminal being recorded
  or a CI log, and it printed every password in the clear with no way to ask it not to. Masking is
  applied when a value is printed, never before the two sides are compared, so a password that changed
  is still reported as changed; only its value is withheld. **Breaking** for anything parsing `--diff`
  output that expects values in the clear: add `--no-filter`.
- The `Gemfile` sourced gems over `http://`.
- The CI workflow now declares `permissions: contents: read` rather than taking the repository default
  for `GITHUB_TOKEN`.

### Documentation

- **ERB in a file passed to `--import` or `--diff` is now documented**, having been evaluated all along
  without being written down anywhere. It stays evaluated, and by both commands: a diff exists to show
  what an import will do, so it has to evaluate whatever the import will. This matches the `file`
  provider, which passes the file it reads through ERB, and Rails, which does the same for
  `database.yml`. The consequence, that a transfer file is code and running either command on one runs
  it, is stated in [Command Line](https://config.reidmorrison.com/cli.html).
- What a value in the central store is trusted to do now has a section of its own,
  [What the store is trusted to do](https://config.reidmorrison.com/interpolation.html). `${env:NAME}`
  reads the process environment and an absolute `__import__` reads another path, so write access to a
  path is closer to read access to the environment and the store of every process that loads it than it
  looks. Referenced from the SSM IAM policy and from `interpolate:`.


### Breaking

- Raise the supported Ruby floor to 3.2. The gemspec declared 2.3 and rubocop targeted 2.5, while
  CI has only ever tested 3.2 and up.
- `key?` now returns true for a key that is supplied only by an environment variable, whenever
  `SecretConfig.check_env_var?` is true. It read the in-memory cache directly, so it disagreed with
  `[]` and `fetch`, which have always honored the override. Code that used `key?` to ask specifically
  whether the central store holds a key, rather than whether a value is available, gets a different
  answer now; set `SecretConfig.check_env_var = false` to restore the old meaning.
- Reading a key that exists only as an environment variable no longer writes it into the cache. The
  memoization was what made `key?` change its answer mid-process, and it also leaked the key into
  `configuration` output once it had been read. As a result, a change to an environment variable that
  has no matching key in the central store now takes effect on the next read rather than being pinned
  to the value seen at the first read. Overrides of keys that are in the store are still applied at
  load time, so those still require a `refresh!` to pick up a change, as before.
- `fetch` now calls a supplied block when the key is missing, whether or not `default:` was also
  supplied. The missing-key check ran first, so a block on its own raised `MissingMandatoryKey` and
  was only ever consulted alongside a `default:` that it then took precedence over. Code that relies
  on `fetch(key) { ... }` raising gets the block's value instead now; drop the block to keep raising.

### Deprecated

- The import-time token `$(random)` is renamed to `__generate__`, since a single character was all that
  separated it from the `${random}` interpolation, which has very different semantics: `$(random)` is
  materialized once during a CLI `--import` and persisted, whereas `${random}` is re-evaluated on every
  startup and `refresh!`. `$(random)` still works and still honors `--random_size`, but now prints a
  deprecation warning on stderr and will be removed in the next major release.
- `--random_size` is deprecated in favor of `__generate__:size`. The flag set one size for every
  generated value in the import, so two keys needing different sizes meant two separate imports. It
  still works and still sets the default for a bare `__generate__`, but warns when supplied.

Set `SECRET_CONFIG_SILENCE_DEPRECATIONS` to any value to suppress these warnings while migrating.

### Added

- An AWS Secrets Manager provider, selected with `:secrets_manager`, **in beta while feedback is
  gathered on [issue 8](https://github.com/reidmorrison/secret_config/issues/8)**, holding one setting per secret so
  that a tree can move between it and the Parameter Store unchanged. It needs the
  `aws-sdk-secretsmanager` gem, which stays an optional dependency, and takes the same `key_id:` and
  `key_alias:` arguments as the SSM provider. Two differences are worth knowing before choosing it:
  Secrets Manager charges per secret per month, and a delete is scheduled rather than immediate, so the
  key cannot be rewritten until the recovery window elapses. `recovery_window_in_days:` sets that
  window, between 7 and 30, defaulting to 30. See
  [Providers](https://config.reidmorrison.com/providers.html).
- `secret-config --provider secrets_manager` runs every command against Secrets Manager, other than
  `--delete-tree`, which that store cannot make immediate.
- `SecretConfig.use` accepts `interpolate:`, which was previously reachable only by constructing a
  `Registry` directly. It defaults to `true`, so existing calls are unaffected.
- `__generate__:size` sets the number of bytes to generate for a single key, overriding `--random_size`
  for that key only. A value that begins with `__generate__` but matches neither form, such as
  `__generate__:abc` or `__generate__:0`, now raises rather than being imported as a literal string.
- Documentation for `__import__` and `__value__` in the
  [Guide](https://config.reidmorrison.com/guide.html).
- `secret-config --provider file` now works. `--provider`'s help text has always advertised
  `[ssm | file]`, but only `ssm` was ever built, so anything else raised
  `ArgumentError: Invalid provider`. Every command except `--console` now runs against a local YAML
  file with no AWS credentials, which makes it possible to inspect or edit `config/application.yml`
  directly, and to rehearse an import before running it against SSM.
- `--provider-file FILE_NAME` selects the file that `--provider file` reads and writes. It is separate
  from `--file`, which remains the file that `--export`, `--import` and `--diff` transfer to or from.
  It defaults to the new `SECRET_CONFIG_FILE_NAME` environment variable, then `config/application.yml`.
- `SECRET_CONFIG_FILE_NAME` sets the file that `Providers::File` reads and writes. With
  `SECRET_CONFIG_PROVIDER=file` there was previously no way to change it from `config/application.yml`.
  An explicit `file_name:` argument still wins.
- `Providers::File#set` and `#delete` are implemented, so the file provider is writable. A key that is
  both a value and a node keeps its own value under `__value__`, and a delete prunes the nodes it
  leaves empty. Writes rewrite the file from its parsed contents, so comments and formatting are lost,
  and a file containing ERB is refused rather than written, since rewriting it would silently replace
  the ERB with its evaluated result.
- `Providers::File` no longer requires the file to exist before it is constructed. Reads still raise
  `ConfigurationError` when it is missing, writes create it, so `--import` can bootstrap a new store.
  `SecretConfig.use(:file)` fails at the same point as before, since `Registry#refresh!` reads
  immediately.

### Fixed

- The file provider compared `Psych::VERSION` to `"4.0"` as a String, so Psych 10 would sort below 4.0
  and fall back to the Psych 3 branch, losing `aliases: true` and breaking any config file using YAML
  anchors. Compared as `Gem::Version` now. No exposure either way: `YAML.load` has been safe by default
  since Psych 4.
- A `${...}` token given the wrong number of arguments, such as `${pid:extra}`, raised a bare
  `ArgumentError`. It raises `InvalidInterpolation` naming the token, like every other bad token.
- `${random:size}` raised `NoMethodError` instead of generating a value. Every interpolation argument
  is parsed out of the value as a String, and `SecureRandom.urlsafe_base64` requires an Integer. The
  size is now converted, and a near miss such as `${random:abc}` or `${random:0}` raises
  `ConfigurationError` rather than silently generating nothing, matching what `__generate__:abc` does
  on import. The test covering this stubbed `SecureRandom.urlsafe_base64`, which swallowed the argument
  and hid the failure; it no longer stubs it.
- `secret-config --console` raised `NameError: uninitialized constant SecretConfig::CLI::IRB`. The
  `require "irb"` was removed because IRB stops being a default gem in Ruby 4.0, which leaves an
  unconditional require warning under bundler, but the `IRB.start` call it fed was left behind. IRB is
  now required inside the command, so it is loaded only when it is used, and a missing IRB raises a
  `LoadError` naming the gem to add.
- `secret-config --set KEY=VALUE` no longer truncates values containing `=`. Base64 encryption keys
  and initialization vectors are padded with `=` and were being silently written without the padding.
- `--file` no longer declares the short option `-f`, which was already taken by `--fetch`.
  OptionParser gave `-f` to `--fetch`, so no working invocation changes meaning.
- `Providers::File#fetch` and the "path not found" error in `Providers::File#each` raised `NameError`
  instead of doing their job.
- `secret-config --import --force` no longer regenerates values that are already present. `--force`
  passed an empty hash in place of the current values, which was intended only to defeat the
  skip-unchanged-keys optimization, but also defeated the guard that leaves an existing generated value
  alone. Forcing an import to re-encrypt under a new KMS key, the documented use case, silently replaced
  every `$(random)` secret in the source with a new one.
- A cycle in `__import__` values that runs through an absolute path now raises
  `SecretConfig::ConfigurationError` with the cycle in the message, instead of `SystemStackError`.
  Every absolute import is resolved by a separate provider fetch that built its own parser, so the
  cycle tracking that already guarded relative imports could not see across the fetch. The paths
  being fetched are now threaded through, and only a path that recurs raises: importing the same
  path from two places, or importing a path nested under one already fetched, still works.
- An `__import__` of a node that is itself an import now resolves regardless of the order the two
  nodes are declared in. Previously the unresolved `__import__` key was copied across instead of the
  settings behind it, leaving a reserved key visible in the registry. Circular imports raise
  `SecretConfig::ConfigurationError` rather than recursing.
- `Providers::File#fetch` returns the value of a key that is both a value and a node, rather than
  `nil`. Such a key holds its own value under `__value__`, which is what `#each` has always yielded
  for it, so the two disagreed. A key that is only a node still returns `nil`.

### Changed

- Correct the SSM retry defaults in the documentation (`retry_count` 25, `retry_max_ms` 10_000) and
  describe the retry sleep as the uniform random interval it is, rather than an exponential backoff.
- Remove `array` from the documented list of types. Arrays are produced by supplying `separator:`.
- Remove the half-implemented `${fetch: ...}` remnants.

### Development

- Add rubocop, with the `rubocop-minitest` and `rubocop-rake` plugins, to the default rake task and CI.
- Add SimpleCov, and raise test coverage from 57% to 98%.
- Add Ruby 4.0 to the CI matrix.
- Split `SecretConfig::CLI` into `CLI::Options` (argument parsing), `CLI::ConfigFile` (the YAML or JSON
  file that `--export`, `--import` and `--diff` transfer to or from), `CLI::Differ` and `CLI::Importer`,
  leaving the command dispatch behind. The `Metrics` rubocop cops no longer exclude `cli.rb`. `CLI` still
  answers every option as a reader, and `Utils.sort_by_key!` is the one method the split promoted to a
  shared helper. The unused `copy_path`, `diff_path` and `import_path` readers, which no option ever set,
  are removed.
- Remove `TECH_DEBT.md`. Every item it tracked has been worked through, and each one is recorded above.

## [1.0.0] - 2022-03-11

### Fixed

- Handle a `nil` default value on `fetch`.

## [0.10.4] - 2021-08-06

### Added

- `${select:a,b,c}` string interpolation, which randomly selects one of the supplied values.

### Fixed

- Only delete a key from the local cache on `refresh!` when it is no longer present in the provider.

## [0.10.3] - 2021-01-24

### Breaking

- String interpolation uses `${...}` instead of `%{...}`. Change all interpolated strings to `$`
  before upgrading.

### Added

- `${env:name}` raises `SecretConfig::MissingEnvironmentVariable` when the environment variable is
  not defined, and `${env:name,default}` supplies a default instead.
- `SECRET_CONFIG_KEY_ALIAS` is used as the default value for the CLI.
- Support for a root path.
- A `default` can supply an array type directly.

### Changed

- Switch from Awesome Print to Amazing Print.
- Publish the documentation site.

## [0.9.0] - 2020-05-28

### Breaking

- The command line program is named `secret-config`, not `secret_config`, and its arguments changed
  to be consistent across operations. Run `secret-config --help` for the current arguments.

### Added

- `__import__`, which copies another subtree into its parent node.
- Colorized CLI output.

## [0.8.0] - 2020-04-29

### Added

- `__import__` resolves both absolute and relative paths.
- `SecretConfig.configure`, which supplies the root path once for a block of lookups.
- The `ssm` provider accepts any `Aws::SSM::Client` initialization parameter.

## [0.7.1] - 2020-03-10

### Added

- `--force` on import, to set all values rather than only the changed ones. Useful when changing the
  KMS key.

## [0.7.0] - 2020-02-24

### Added

- String interpolation of values, evaluated at load and on every `refresh!`.
- Environment variable overrides apply to keys that are not present in the registry at startup.

### Changed

- Use SSM intelligent tiering, to support larger values.
- Strip values in the string interpolator.

## [0.6.4] - 2019-11-21

### Fixed

- The SSM throttle retry mechanism.

## [0.6.3] - 2019-11-19

### Changed

- Filter any value whose key ends with `key`.

## [0.6.2] - 2019-10-27

### Added

- The `json` type.
- Delete a key directly from the CLI.
- Import and diff against an existing path.

## [0.6.1] - 2019-10-14

### Fixed

- Roll back an incorrect automated rubocop correction.

## [0.6.0] - 2019-10-11

### Added

- Support for nodes that are both a value and a branch, via `__value__`.
- `fetch`, `set`, and `delete` on the providers.
- KMS key alias support in the registry itself.

### Changed

- Filtered values are ignored during an import or a diff.

## [0.5.3] - 2019-10-02

### Added

- Support for a KMS key alias.

### Fixed

- Keys at the root level.

### Changed

- Sort config keys.

## [0.5.2] - 2019-07-30

### Fixed

- Add the missing `delete` method.

## [0.5.1] - 2019-07-16

### Fixed

- `Registry#set`.

## [0.5.0] - 2019-05-14

### Added

- The `--diff` and `--prune` CLI options.

## [0.4.5] - 2019-05-01

### Fixed

- Include the binary in the gemspec.

## [0.4.4] - 2019-05-01

### Fixed

- Restore the load path for `bin`.

## [0.4.3] - 2019-04-25

### Fixed

- The `ConfigurationError` class.

## [0.4.2] - 2019-04-25

### Fixed

- Support a default value of `false`.

## [0.4.1] - 2019-04-19

### Added

- A CLI console.

## [0.4.0] - 2019-04-18

### Added

- A CLI to import and export configuration data as YAML or JSON.

## [0.3.1] - 2019-04-17

### Changed

- AWS SSM Parameter Store is a soft dependency, so `aws-sdk-ssm` is only required when the `ssm`
  provider is used.

## [0.3.0] - 2019-04-16

### Added

- Environment variables override values from the parameter store.

## [0.2.0] - 2019-04-15

### Added

- Second iteration of the API.

## [0.1.0] - 2019-04-12

Initial release.

[1.0.0]: https://github.com/reidmorrison/secret_config/compare/v0.10.4...v1.0.0
[0.10.4]: https://github.com/reidmorrison/secret_config/compare/v0.10.3...v0.10.4
[0.10.3]: https://github.com/reidmorrison/secret_config/compare/v0.9.0...v0.10.3
[0.9.0]: https://github.com/reidmorrison/secret_config/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/reidmorrison/secret_config/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/reidmorrison/secret_config/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/reidmorrison/secret_config/compare/v0.6.4...v0.7.0
[0.6.4]: https://github.com/reidmorrison/secret_config/compare/v0.6.3...v0.6.4
[0.6.3]: https://github.com/reidmorrison/secret_config/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/reidmorrison/secret_config/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/reidmorrison/secret_config/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/reidmorrison/secret_config/compare/v0.5.3...v0.6.0
[0.5.3]: https://github.com/reidmorrison/secret_config/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/reidmorrison/secret_config/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/reidmorrison/secret_config/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/reidmorrison/secret_config/compare/v0.4.5...v0.5.0
[0.4.5]: https://github.com/reidmorrison/secret_config/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/reidmorrison/secret_config/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/reidmorrison/secret_config/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/reidmorrison/secret_config/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/reidmorrison/secret_config/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/reidmorrison/secret_config/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/reidmorrison/secret_config/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/reidmorrison/secret_config/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/reidmorrison/secret_config/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/reidmorrison/secret_config/releases/tag/v0.1.0
