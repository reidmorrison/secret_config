# Tech Debt

Known issues and open design questions, from a review of the code against the docs in [docs/](docs/).
Each item below was reproduced or verified, not inferred from reading alone.

**Target release: v2.** Several of these are deliberately breaking, so they are held for the next major
release rather than a 1.x. Items marked **[breaking]** change observable behavior for existing users;
the rest are safe to ship at any time. See the versioning section of [CLAUDE.md](CLAUDE.md).

## Bugs

### 1. `Providers::File#fetch` raises `NameError`

[lib/secret_config/providers/file.rb:27-30](lib/secret_config/providers/file.rb#L27-L30) calls
`fetch_path(path)`, but `path` is neither a parameter nor an accessor on the class. The parameter is
named `_key` and is unused.

    fetch => NameError: undefined local variable or method 'path'

`Registry` only calls `provider.each`, so nothing in the library reaches this method. Decide whether to
delete it or make it work, so that an absolute `__import__` can resolve against the file provider.

### 2. "Path not found" in `Providers::File#each` raises `NameError`

[lib/secret_config/providers/file.rb:20](lib/secret_config/providers/file.rb#L20) interpolates `paths`,
which is a local variable inside `fetch_path`, not in scope at the raise site.

    each(missing path) => NameError: undefined local variable or method 'paths'

The intended `ConfigurationError` never surfaces, so a typo'd path in `application.yml` gives a developer
a `NameError` instead of a useful message.

### 3. `--set` truncates any value containing `=`

[lib/secret_config/cli.rb:141](lib/secret_config/cli.rb#L141) uses `param.split("=")`, which splits on
every `=` rather than just the first, so the value is silently truncated:

    --set symmetric_encryption/key=QUJDREVG12345=
    => key "symmetric_encryption/key", value "QUJDREVG12345"

The trailing `=` is gone. This matters specifically for this gem, since base64 encryption keys and
initialization vectors are padded with `=` and are exactly the kind of value stored here. A truncated key
is written without error and fails later at decryption time.

`param.split("=", 2)` fixes it. Locked in by a test in [test/cli_test.rb](test/cli_test.rb) that documents
the current behavior; update that test when fixing.

### 4. `-f` is bound to both `--file` and `--fetch`

[lib/secret_config/cli.rb:128](lib/secret_config/cli.rb#L128) defines `-f, --file` and
[cli.rb:147](lib/secret_config/cli.rb#L147) defines `-f, --fetch`. OptionParser lets the later definition
win, so `--file` has no working short form:

    -f application.yml  =>  fetch_key "application.yml", file_name nil

Anyone following the docs and using `-f` to name an import or export file silently runs a fetch instead.
Give `--fetch` a different short option, or drop the short form from one of them.

### 5. `key?` and `[]` disagree about env-var-only keys **[breaking]**

`Registry#[]` memoizes an env-var override into the cache on a miss, but `Registry#key?` reads the cache
directly, so the answer changes depending on whether the key has been read yet.

    key? before read: false
    [] read: "x"
    key? after read: true

This has a real consequence for the key-rotation example in [docs/config.md](docs/config.md), which gates
the secondary cipher on `key?('symmetric_encryption/old/key')`. Rotating keys via
`SYMMETRIC_ENCRYPTION_OLD_KEY` alone yields `false` and no secondary cipher, even though `fetch` on the
same key returns the value.

Decide whether `key?` should consult env vars when `check_env_var?` is true.

## Doc and code drift

### 6. SSM retry defaults are documented incorrectly

[docs/config.md](docs/config.md) documents `retry_count` default 10 and `retry_max_ms` default 3_000.
[lib/secret_config/providers/ssm.rb:17-18](lib/secret_config/providers/ssm.rb#L17-L18) uses 25 and 10_000.

Relatedly, [docs/index.md](docs/index.md) describes throttling retries as "exponential backoffs", but the
implementation is deliberately uniform jitter (`rand(retry_max_ms)`), with a comment explaining that this
spreads out retries across servers during a high volume restart. The doc should describe the actual
strategy.

Correcting the docs is non-breaking. Changing the code defaults to match the docs would be **[breaking]**,
since it would quadruple the retry count and shorten the sleep window for existing users.

### 7. `array` is documented as a supported type but is not one

[docs/index.md](docs/index.md) lists `array` alongside `integer`, `float`, `string`, `boolean`, `symbol`,
and `json`. `Registry#convert_type` has no such branch:

    fetch(type: :array) => ArgumentError: Unrecognized type:array

Arrays are produced by `separator:` instead. Either drop `array` from the docs or add it as an alias.

### 8. `SECRET_CONFIG_ACCOUNT_ID` is documented as a required env var but is unused by the library

The env var table in [docs/config.md](docs/config.md) lists it with priority "required". It appears
nowhere in `lib/`. Its only use is [test/providers/ssm_test.rb:43](test/providers/ssm_test.rb#L43), where
it builds a role ARN. The row also says "used in `rspec`", but the test suite is Minitest.

Move it to a contributor doc or remove the row.

### 9. Three spellings of the import-time random token

The constant is `$(random)` and the `--random_size` help text agrees, but the prose at
[docs/cli.md:114](docs/cli.md#L114) tells users to set the value to `$random`, which will not match the
`value.to_s.strip == RANDOM` comparison in the CLI.

## Design questions

### 10. `$(random)` and `${random}` are near-identical syntax for different features

`$(random)` is materialized once during a CLI `--import` and persisted to the store. `${random}` is
regenerated on every startup and every `refresh!`. A user who writes `${random}` for a database password
gets a value that silently changes out from under them.

Decide whether the collision is acceptable, and at minimum document the distinction in
[docs/interpolation.md](docs/interpolation.md). Documenting is non-breaking; changing either token's
syntax is **[breaking]** and would need a v2 upgrade note, in the style of the `%{}` to `${}` migration
already described in [README.md](README.md).

### 11. `__import__` is effectively undocumented

Its only mention across all of `docs/` is inside the `--interpolate` flag description in
[docs/cli.md](docs/cli.md). The same applies to `__value__` (`NODE_KEY`), which users hit as soon as a
node is both a value and a branch.

Decide whether `__import__` is deliberately unadvertised because of its stated limits (imports cannot
reference other imports) or whether this is simply a documentation gap.

### 12. `${fetch: ...}` is half-implemented

`apply_fetches` is commented out in [lib/secret_config/parser.rb:32-34](lib/secret_config/parser.rb#L32-L34),
along with a commented-out `"${fetch: /test/my_application/mysql/database }"` in
[test/config/application.yml](test/config/application.yml). There is also a leftover `binding.irb` comment
in `apply_imports`. Either finish the feature or remove the remnants.

### 13. `interpolate:` is unreachable through the public API

`Registry` accepts `interpolate:`, but `SecretConfig.use(provider, path:, **args)` funnels everything
other than `path` into `provider_args`, so it reaches the provider constructor instead:

    use(interpolate: false) => ArgumentError: unknown keyword: :interpolate

The concept is already user facing via the CLI's `--interpolate`. Consider extracting `interpolate:`
explicitly in `use`.

### 14. Supported Ruby version floor is inconsistent **[breaking]** — RESOLVED

The gemspec declared `required_ruby_version >= 2.3` and [.rubocop.yml](.rubocop.yml) targeted 2.5, while
[.github/workflows/ci.yml](.github/workflows/ci.yml) covers 3.2 through 4.0.

Both were raised to 3.2 to match what is actually tested. This is a breaking change and ships in v2.

### 15. `cli.rb` is excluded from the `Metrics/*` cops

`Metrics/AbcSize`, `ClassLength`, `CyclomaticComplexity`, `MethodLength`, and `BlockLength` all exclude
`cli.rb` in [.rubocop.yml](.rubocop.yml). The class is 359 lines, `run!` has a cyclomatic complexity of 16,
and `parser` is a 78 line method.

The exclusions are there because the command implementations have no test coverage, so a refactor cannot
be verified. Cover them first, then split the class and remove the exclusions.

### 16. No CHANGELOG.md

The gemspec metadata omits `changelog_uri` because there is no changelog to point at, unlike the sibling
gems. Worth adding before the v2 release, since v2 carries breaking changes that users need to read about.

## Not tracked here

Rubocop reports no offenses, runs as part of the default rake task, and has its own CI job.
