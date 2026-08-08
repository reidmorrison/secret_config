# Tech Debt

Known issues and open design questions. Each item below was reproduced or verified, not inferred from
reading alone. Resolved items are removed from this file once shipped; [CHANGELOG.md](CHANGELOG.md)
carries the history.

**Target release: v2.** Items marked **[breaking]** change observable behavior for existing users and are
held for the next major release rather than a 1.x. The rest are safe to ship at any time. See the
versioning section of [CLAUDE.md](CLAUDE.md).

## Design questions

### 1. `cli.rb` is excluded from the `Metrics/*` cops

`Metrics/AbcSize`, `ClassLength`, `CyclomaticComplexity`, `MethodLength`, and `BlockLength` all exclude
`cli.rb` in [.rubocop.yml](.rubocop.yml). Against the default config it is 526 lines with a class body of
396, `run!` has a cyclomatic complexity of 16, and `parser` is a 92 line method.

The exclusions are there because the command implementations had no test coverage, so a refactor could not
be verified. Building the file provider into the CLI removed that blocker: `cli.rb` is now at 92.0%, since
every command except `--console` can be driven against a local file without AWS credentials. Splitting the
class and removing the exclusions is now safe to do. What remains uncovered is `--console`, the SSM
branches of `#provider_instance`, and the stdin/stdout ends of `read_file` and `write_file`.

## Not tracked here

Rubocop reports no offenses, runs as part of the default rake task, and has its own CI job.
