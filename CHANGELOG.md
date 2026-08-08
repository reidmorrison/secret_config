# Changelog

All notable changes to this project are documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/). Entries for releases prior to
v1.0.1 were reconstructed from the git history and are summaries rather than exhaustive lists.

## Unreleased

Targeted at v2, since it carries breaking changes.

### Breaking

- Raise the supported Ruby floor to 3.2. The gemspec declared 2.3 and rubocop targeted 2.5, while
  CI has only ever tested 3.2 and up.

### Added

- `SecretConfig.use` accepts `interpolate:`, which was previously reachable only by constructing a
  `Registry` directly. It defaults to `true`, so existing calls are unaffected.
- Documentation for `__import__` and `__value__` in the
  [Guide](https://config.reidmorrison.com/guide.html).

### Fixed

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
- An `__import__` of a node that is itself an import now resolves regardless of the order the two
  nodes are declared in. Previously the unresolved `__import__` key was copied across instead of the
  settings behind it, leaving a reserved key visible in the registry. Circular imports raise
  `SecretConfig::ConfigurationError` rather than recursing.

### Changed

- Correct the SSM retry defaults in the documentation (`retry_count` 25, `retry_max_ms` 10_000) and
  describe the retry sleep as the uniform random interval it is, rather than an exponential backoff.
- Remove `array` from the documented list of types. Arrays are produced by supplying `separator:`.
- Remove the half-implemented `${fetch: ...}` remnants.

### Development

- Add rubocop, with the `rubocop-minitest` and `rubocop-rake` plugins, to the default rake task and CI.
- Add SimpleCov, and raise test coverage from 57% to 77%.
- Add Ruby 4.0 to the CI matrix.

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
