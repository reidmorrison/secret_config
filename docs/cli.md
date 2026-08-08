---
layout: default
---

## Command Line
{:.no_toc}

**Contents**

* TOC
{:toc}

`secret-config` manages the central store: importing settings into it, exporting them back out, diffing
a candidate file against what is there, and editing individual keys.

It talks to a provider directly rather than through the application's registry, so it works against any
path without `SECRET_CONFIG_PATH` being set, and it does not load your application.

Every command runs against either provider. `--provider file` works on a local YAML file with no AWS
credentials, which is the best way to learn the tool and to rehearse an import before running it for
real. The steps below start there and move to SSM at Step 4.

## Step 1: Look at what is in a store

Start with the file every Rails application already has:

    secret-config --provider file --export /development

With no `--file`, the export goes to stdout. Passwords and keys are masked as `[FILTERED]`, which is
what makes this safe to paste into a ticket.

To see the real values:

    secret-config --provider file --export /development --no-filter

`--provider file` reads `config/application.yml` by default. Point it elsewhere with
`--provider-file`, which is separate from `--file`:

    secret-config --provider file --provider-file config/settings.yml --export /development

The default comes from the `SECRET_CONFIG_FILE_NAME` environment variable, then
`config/application.yml`.

## Step 2: Read, write and delete one key

    secret-config --provider file --fetch /development/mysql/host
    secret-config --provider file --set /development/mysql/host=localhost
    secret-config --provider file --delete /development/mysql/host

Note that these take **absolute** paths. The CLI has no root path of its own, unlike the application
registry, so every key is given in full.

`--set` splits on the first `=` only, so a value may contain more, which matters for base64 keys and
initialization vectors:

    secret-config --provider file --set /development/symmetric_encryption/key=QUJDREVG12345=

To remove an entire subtree:

    secret-config --provider file --delete-tree /development/mongo

Writes rewrite the whole file from its parsed contents, so comments and formatting are lost, and a file
containing ERB is refused rather than written. See [Providers](providers).

## Step 3: Prepare a file for an environment

To get settings into a production store, first write them as a YAML file. This looks like
`application.yml` with one difference: it holds a single environment, so there is no `development` or
`test` key at the top:

~~~yaml
mysql:
  database: my_application_production
  username: my_application
  password: secret_configrules
  host:     mysql_server.example.net

mongo:
  database:  my_application_production
  primary:   mongo_primary.example.net:27017
  secondary: mongo_secondary.example.net:27017

secrets:
  secret_key_base: somereallylongproductionstring
~~~

Rehearse the import against a local file first, which creates it if it does not exist:

    secret-config --provider file --provider-file config/production_rehearsal.yml \
      --import /production/my_application --file production.yml

Then export it back to confirm it landed the way you expected:

    secret-config --provider file --provider-file config/production_rehearsal.yml \
      --export /production/my_application --no-filter

## Step 4: Import into AWS SSM Parameter Store

`--provider ssm` is the default, so it can be left off. This needs AWS credentials and the
`aws-sdk-ssm` gem; see [Providers](providers).

    secret-config --import /production/my_application --file production.yml

Every value is written as an encrypted `SecureString`. To use a custom KMS key rather than the account
default:

    secret-config --import /production/my_application --file production.yml \
      --key_id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

Or by alias:

    secret-config --import /production/my_application --file production.yml --key_alias my_key_alias

With no `--file`, the import reads stdin, so it composes with other tools:

    my-secret-generator | secret-config --import /production/my_application

## Step 5: Diff before importing

Never import into a live environment without looking first:

    secret-config --diff /production/my_application --file production.yml

The output marks each difference:

    + Adding a new key to the registry.
    - The key will be removed from the registry during the import if --prune is specified.
    * The value for that key will change during an import.

By default an import only adds and updates. Keys in the store that are absent from the file are left
alone. `--prune` removes them, making the store match the file exactly:

    secret-config --import /production/my_application --file production.yml --prune

Run the diff first, and read the `-` lines. That is the list `--prune` will delete.

## Step 6: Export for review or backup

    secret-config --export /production/my_application --file production.yml

Filtered by default. Add `--no-filter` for the real values, which is what a backup needs:

    secret-config --export /production/my_application --file production.yml --no-filter

The format follows the file extension, so `.json` gives JSON:

    secret-config --export /production/my_application --file production.json

An export leaves `${...}` and `__import__` markup exactly as it is stored, which is what makes an
export round-trip safely back through `--import`. Pass `--interpolate` to evaluate them instead, which
produces a snapshot of what the application would actually see:

    secret-config --export /production/my_application --file snapshot.yml --interpolate

Do not import an interpolated export. It will replace shared imports with copies, and any `${random}`
with one frozen value.

## Step 7: Copy a path to spin up a tenant

`--path` reads from another path in the store instead of a file, which copies a subtree:

    secret-config --import /tenant73/my_application --path /production/my_application

The usual pattern is to keep a "master" or "common" path holding the settings a new stack should start
from, copy it, and then adjust the handful of values specific to the new tenant.

A copy is literal: every value in the source, including its passwords, is written to the destination as
it stands. To give each tenant its own credentials, see Step 8.

`--path` works with `--diff` too, which answers "how does this tenant differ from the master copy":

    secret-config --diff /tenant73/my_application --path /production/my_application

## Step 8: Generate a password per tenant

A new tenant should not share the passwords of the one it was copied from. Write `__generate__` as the
value, and the import gives the destination a secure random value:

~~~yaml
mysql:
  host:     mysql_server.example.net
  password: __generate__
~~~

The value must be exactly `__generate__`, ignoring surrounding spaces.

**Keep the template as a file, not as a path.** `__generate__` is materialized during the import, so the
path it was imported into holds a real password from then on, and Step 7's path-to-path copy duplicates
that password rather than generating a new one. Import the template file into each tenant instead:

    secret-config --import /tenant73/my_application --file template.yml
    secret-config --import /tenant74/my_application --file template.yml

Those two tenants get different passwords, and share everything else the template specifies.

Existing values are left alone, so re-running the import does not replace a password that was already
generated. This holds under `--force` as well: forcing an import rewrites every key so that it is
re-encrypted under a new KMS key, but it never regenerates a value that is already present.

The default length is 32 bytes. Supply the size on the token to change it for that key alone:

~~~yaml
mysql:
  password: __generate__        # 32 bytes
  api_key:  __generate__:64     # 64 bytes
~~~

The size must be written tight against the colon. `__generate__: 64` is not valid YAML in a value
position, since YAML reads the `: ` as the start of a nested mapping.

A value that starts with `__generate__` but is neither of those two forms, such as `__generate__:abc` or
`__generate__:0`, raises rather than being imported as a literal string, on the grounds that it is far
more likely to be a typo than an intended value.

### `__generate__` is not `${random}`

Both produce a random value, and they behave very differently:

* `__generate__` is materialized once, by the CLI, during an `--import`. The generated value is written
  to the store and stays there.
* `${random}` is a [string interpolation](interpolation). It is evaluated by the application every time
  the registry is loaded or refreshed, so it produces a different value on every restart.

Use `__generate__` for anything that has to stay the same after it is generated, such as a database
password. `${random}` is only suitable for values that are genuinely disposable within a single process.

## Step 9: Rotate a KMS key

`--force` rewrites every key rather than only the changed ones, which re-encrypts the whole path under
a new key:

    secret-config --import /production/my_application --path /production/my_application \
      --force --key_id "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"

Importing a path onto itself is deliberate here: nothing changes except the key the values are
encrypted with. Generated values are preserved, as covered in Step 8.

## Console

    secret-config --console

Intended to open an interactive Ruby session with the registry loaded, for exploring a store.

**This currently raises `NameError: uninitialized constant SecretConfig::CLI::IRB`** on every provider,
because IRB is no longer required. Until that is fixed, get the same thing from a plain IRB session:

~~~ruby
require "secret_config"
SecretConfig.use(:file, path: "/development")
SecretConfig.configuration
~~~

## Deprecated: `$(random)` and `--random_size`

`__generate__` was previously spelled `$(random)`, which was too easily confused with the `${random}`
interpolation. The old spelling still works, but prints a deprecation warning on stderr and will be
removed in the next major release. It does not accept a per-key size.

`--random_size` is deprecated alongside it. It set the size for every generated value in an import, so
two keys needing different sizes meant two separate imports. `__generate__:size` replaces it and is set
per key. The flag still works, and still sets the default for values written as a bare `__generate__`,
but warns when supplied.

Set `SECRET_CONFIG_SILENCE_DEPRECATIONS` to any value to suppress both warnings while migrating.

## All options

~~~
secret-config [options]
    -e, --export SOURCE_PATH         Export configuration. Use --file to specify the file name, otherwise stdout is used.
    -i, --import TARGET_PATH         Import configuration. Use --file to specify the file name, --path for the SOURCE_PATH, otherwise stdin is used.
        --diff TARGET_PATH           Compare configuration to this path. Use --file to specify the source file name, --path for the SOURCE_PATH, otherwise stdin is used.
        --file FILE_NAME             Import/Export/Diff to/from this file.
    -p, --path PATH                  Import/Export/Diff to/from this path.
    -s, --set KEY=VALUE              Set one key to value. Example: --set mysql/database=localhost
    -f, --fetch KEY                  Fetch the value for one setting. Example: --fetch mysql/database.
    -d, --delete KEY                 Delete one specific key.
    -r, --delete-tree PATH           Recursively delete all keys under the specified path.
        --provider PROVIDER          Provider to use. [ssm | file]. Default: ssm
        --provider-file FILE_NAME    For --provider file only. The config file to read and write. Default: $SECRET_CONFIG_FILE_NAME, then config/application.yml.
        --key_id KEY_ID              For --import only. Encrypt config settings with this AWS KMS key id. Default: AWS Default key.
        --key_alias KEY_ALIAS        For --import only. Encrypt config settings with this AWS KMS alias.
        --no-filter                  For --export only. Do not filter passwords and keys.
        --interpolate                For --export only. Evaluate string interpolation and __import__.
        --prune                      For --import only. During import delete all existing keys for which there is no key in the import file. Only works with --import.
        --force                      For --import only. Overwrite all values, not just the changed ones. Useful for changing the KMS key.
        --random_size INTEGER        Deprecated. For --import only. Default size in bytes to use when generating values when __generate__ is encountered in the source. Supply the size on each value instead, as __generate__:size. Default: 32
    -c, --console                    Start interactive console.
    -v, --version                    Display Secret Config version.
    -h, --help                       Prints this help.
~~~

Note that `-f` is `--fetch`. `--file` has no short form.

## Next steps

* [Providers](providers): what each provider supports, and the IAM policy the CLI needs.
* [Interpolation](interpolation): the markup that exports preserve.
* [Rails](rails): deploying what you just imported.
