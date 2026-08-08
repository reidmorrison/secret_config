# Tech Debt

Known issues and open design questions, from a review of the code against the docs in [docs/](docs/).
Each item below was reproduced or verified, not inferred from reading alone.

**Target release: v2.** Several of these are deliberately breaking, so they are held for the next major
release rather than a 1.x. Items marked **[breaking]** change observable behavior for existing users;
the rest are safe to ship at any time. See the versioning section of [CLAUDE.md](CLAUDE.md).

## Bugs

### 1. `Providers::File#fetch` raises `NameError` — RESOLVED

`fetch` called `fetch_path(path)`, but `path` was neither a parameter nor an accessor on the class. The
parameter was named `_key` and was unused.

    fetch => NameError: undefined local variable or method 'path'

Fixed in `c2690b7`: the parameter is now `key` and is passed to `fetch_path`, so an absolute `__import__`
can resolve against the file provider. Covered by [test/providers/file_test.rb](test/providers/file_test.rb).

### 2. "Path not found" in `Providers::File#each` raises `NameError` — RESOLVED

The raise site interpolated `paths`, a local variable inside `fetch_path` that was not in scope there.

    each(missing path) => NameError: undefined local variable or method 'paths'

Fixed in `c2690b7`: the message interpolates `path`, so a typo'd path in `application.yml` now raises the
intended `ConfigurationError`.

### 3. `--set` truncates any value containing `=` — RESOLVED

The option handler used `param.split("=")`, which splits on every `=` rather than just the first, so the
value was silently truncated:

    --set symmetric_encryption/key=QUJDREVG12345=
    => key "symmetric_encryption/key", value "QUJDREVG12345"

The trailing `=` was gone. This mattered specifically for this gem, since base64 encryption keys and
initialization vectors are padded with `=` and are exactly the kind of value stored here. A truncated key
was written without error and failed later at decryption time.

Fixed with `param.split("=", 2)`. The guard that rejects a missing value now also rejects an empty one, so
`--set key=` still raises `ArgumentError` as it did before. [test/cli_test.rb](test/cli_test.rb) asserts
that the value is preserved.

### 4. `-f` is bound to both `--file` and `--fetch` — RESOLVED

`-f, --file` and `-f, --fetch` were both defined. OptionParser let the later definition win, so `--file`
had no working short form:

    -f application.yml  =>  fetch_key "application.yml", file_name nil

Fixed by dropping the short form from `--file`, which is what already happened in practice and what
[docs/cli.md](docs/cli.md) already advertised. `-f` remains `--fetch`, so no working invocation changes
meaning.

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

### 6. SSM retry defaults are documented incorrectly — RESOLVED

[docs/config.md](docs/config.md) documented `retry_count` default 10 and `retry_max_ms` default 3_000,
while [lib/secret_config/providers/ssm.rb:16-17](lib/secret_config/providers/ssm.rb#L16-L17) uses 25 and
10_000. [docs/index.md](docs/index.md) also described throttling retries as "exponential backoffs", but the
implementation is deliberately uniform jitter (`rand(retry_max_ms)`), which spreads out retries across
servers during a high volume restart.

Resolved by correcting both docs to match the code, which is non-breaking. Changing the code defaults to
match the old docs would have been **[breaking]**, since it would quadruple the retry count and shorten
the sleep window for existing users.

### 7. `array` is documented as a supported type but is not one — RESOLVED

[docs/index.md](docs/index.md) listed `array` alongside `integer`, `float`, `string`, `boolean`, `symbol`,
and `json`. `Registry#convert_type` has no such branch:

    fetch(type: :array) => ArgumentError: Unrecognized type:array

Arrays are produced by `separator:` instead, as [docs/api.md](docs/api.md) already described. Resolved by
dropping `array` from the type list and pointing at `separator:`, rather than adding a type alias.

### 8. `SECRET_CONFIG_ACCOUNT_ID` is documented as a required env var but is unused by the library — RESOLVED

The env var table in [docs/config.md](docs/config.md) listed it with priority "required". It appears
nowhere in `lib/`. Its only use is [test/providers/ssm_test.rb:43](test/providers/ssm_test.rb#L43), where
it builds a role ARN. The row also said "used in `rspec`", but the test suite is Minitest.

Resolved by removing the row and documenting the env var in [CONTRIBUTING.md](CONTRIBUTING.md), next to
the instructions for running the live SSM test that reads it.

### 9. Three spellings of the import-time random token — RESOLVED

The constant is `$(random)` and the `--random_size` help text agrees, but the prose in
[docs/cli.md](docs/cli.md) told users to set the value to `$random`, which does not match the
`value.to_s.strip == RANDOM` comparison in the CLI.

Resolved by correcting the prose to `$(random)` and stating that the value must match exactly.

## Design questions

### 10. `$(random)` and `${random}` are near-identical syntax for different features

`$(random)` is materialized once during a CLI `--import` and persisted to the store. `${random}` is
regenerated on every startup and every `refresh!`. A user who writes `${random}` for a database password
gets a value that silently changes out from under them.

The documentation half is done: [docs/cli.md](docs/cli.md) now contrasts the two directly and
[docs/interpolation.md](docs/interpolation.md) warns against `${random}` for values that must stay stable.

Still open: whether the near-identical syntax is acceptable at all. Changing either token is **[breaking]**
and would need a v2 upgrade note, in the style of the `%{}` to `${}` migration already described in
[README.md](README.md).

### 11. `__import__` is effectively undocumented — RESOLVED

Its only mention across all of `docs/` was inside the `--interpolate` flag description in
[docs/cli.md](docs/cli.md). The same applied to `__value__` (`NODE_KEY`), which users hit as soon as a
node is both a value and a branch.

Resolved as a documentation gap: [docs/guide.md](docs/guide.md) now covers both, including how relative
and absolute imports resolve, that existing keys win, and that imports are only applied when
interpolation is enabled. Writing it up turned up item 17 below.

### 12. `${fetch: ...}` is half-implemented — RESOLVED

`apply_fetches` was commented out in [lib/secret_config/parser.rb](lib/secret_config/parser.rb), along
with a commented-out `"${fetch: /test/my_application/mysql/database }"` in
[test/config/application.yml](test/config/application.yml), a commented-out `fetch` sketch in
[test/parser_test.rb](test/parser_test.rb), and a leftover `binding.irb` comment in `apply_imports`.

Resolved by removing the remnants rather than finishing the feature, along with the `@fetch_list` and
`@import_list` ivars, which nothing read. `__import__` already covers importing a subtree; nothing in the
docs or the CLI ever advertised `${fetch:}`.

### 13. `interpolate:` is unreachable through the public API — RESOLVED

`Registry` accepted `interpolate:`, but `SecretConfig.use(provider, path:, **args)` funnelled everything
other than `path` into `provider_args`, so it reached the provider constructor instead:

    use(interpolate: false) => ArgumentError: unknown keyword: :interpolate

Resolved by extracting `interpolate:` explicitly in `use`, defaulting to `true`. Additive, so no existing
call changes behavior.

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

### 16. No CHANGELOG.md — RESOLVED

The gemspec metadata omitted `changelog_uri` because there was no changelog to point at, unlike the
sibling gems.

Resolved by adding [CHANGELOG.md](CHANGELOG.md), reconstructed from the git history and the released gem
versions, with an Unreleased section for the v2 work. `changelog_uri` now points at it.

### 17. A forward `__import__` reference leaks an unresolved `__import__` key — RESOLVED

Found while documenting item 11. `Parser#apply_imports` walked the keys once, in read order, so an import
of a node whose own `__import__` had not been resolved yet copied the literal `__import__` key across
instead of the settings behind it:

~~~yaml
early:
  __import__: later
later:
  __import__: base
~~~

    early  => {"__import__" => "base"}    # no settings imported, and a reserved key left in the registry
    later  => {"host" => ..., "port" => ...}

Reversing the order of the two nodes resolved both correctly, so the outcome depended on the order the
provider yielded keys in.

Resolved by having `apply_import` resolve the imports inside the subtree it is about to copy before
copying it, so chained imports work in any order. A cycle would otherwise recurse forever, so the import
keys being resolved are tracked and a circular reference raises `ConfigurationError`. This removes the
"imports cannot reference other imports at this time" limitation the code comment noted.

Note that this covers relative imports. See item 18 for the absolute case.

### 18. Mutually recursive absolute imports overflow the stack

Pre-existing, found while fixing item 17. An absolute `__import__` is resolved by
`Registry#fetch_path`, which builds a fresh `Parser`, so the cycle tracking added in item 17 does not
cross that boundary:

~~~yaml
test:
  a:
    node:
      __import__: /test/b/node
  b:
    node:
      __import__: /test/a/node
~~~

    Registry.new(path: "/test/a", ...) => SystemStackError

The relative equivalent now raises `ConfigurationError` with the cycle in the message, so the two cases
report very differently. Fixing it means threading the set of absolute paths already being fetched
through `Registry#fetch_path` into the `Parser` it creates, and raising when a path recurs.

## Not tracked here

Rubocop reports no offenses, runs as part of the default rake task, and has its own CI job.
