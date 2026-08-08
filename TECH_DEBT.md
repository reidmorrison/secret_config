# Tech Debt

Known issues and open design questions. Each item below was reproduced or verified, not inferred from
reading alone. Resolved items are removed from this file once shipped; [CHANGELOG.md](CHANGELOG.md)
carries the history.

**Target release: v2.** Items marked **[breaking]** change observable behavior for existing users and are
held for the next major release rather than a 1.x. The rest are safe to ship at any time. See the
versioning section of [CLAUDE.md](CLAUDE.md).

## Bugs

### 1. `key?` and `[]` disagree about env-var-only keys **[breaking]**

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

### 2. Mutually recursive absolute imports overflow the stack

An absolute `__import__` is resolved by `Registry#fetch_path`, which builds a fresh `Parser`, so the cycle
tracking that guards relative imports does not cross that boundary:

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

The relative equivalent raises `ConfigurationError` with the cycle in the message, so the two cases report
very differently. Fixing it means threading the set of absolute paths already being fetched through
`Registry#fetch_path` into the `Parser` it creates, and raising when a path recurs.

### 3. `--provider file` is advertised but not built

`CLI#provider_instance` only builds `:ssm` and raises `ArgumentError` for anything else, even though
`--provider`'s help text advertises `[ssm | file]`:

    secret-config --provider file --fetch mysql/host
    => ArgumentError: Invalid provider: file

Either build the file provider or stop advertising it. Building it is the more useful of the two, since it
would let the CLI diff and export a local `application.yml` without AWS credentials. Asserted as current
behavior by the `#provider_instance` test in [test/cli_test.rb](test/cli_test.rb).

### 4. `fetch` consults a block only when a default is also supplied

The missing-key check runs before the block, so a block on its own does not satisfy a missing key:

    fetch("mysql/unknown", default: "unused") { "from_block" }  => "from_block"
    fetch("mysql/unknown") { "from_block" }                     => MissingMandatoryKey

The second form is what a caller would expect to work, and the first is the one that reads as a mistake.
Changing this is **[breaking]** for anyone relying on the current raise. Asserted as current behavior in
[test/registry_test.rb](test/registry_test.rb).

## Design questions

### 5. `cli.rb` is excluded from the `Metrics/*` cops

`Metrics/AbcSize`, `ClassLength`, `CyclomaticComplexity`, `MethodLength`, and `BlockLength` all exclude
`cli.rb` in [.rubocop.yml](.rubocop.yml). Against the default config it is 509 lines with a class body of
386, `run!` has a cyclomatic complexity of 16, and `parser` is an 87 line method.

The exclusions are there because the command implementations have no test coverage, so a refactor cannot
be verified. `#set_config` is now covered, the rest are not. Cover them first, then split the class and
remove the exclusions.

## Not tracked here

Rubocop reports no offenses, runs as part of the default rake task, and has its own CI job.
