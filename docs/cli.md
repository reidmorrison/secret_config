---
layout: default
---

## Command Line Interface

Secret Config has a command line interface for exporting, importing and copying between paths in the registry.

~~~
secret-config [options]
    -e, --export SOURCE_PATH         Export configuration. Use --file to specify the file name, otherwise stdout is used.
    -i, --import TARGET_PATH         Import configuration. Use --file to specify the file name, --path for the SOURCE_PATH, otherwise stdin is used.
        --file FILE_NAME             Import/Export/Diff to/from this file.
    -p, --path PATH                  Import/Export/Diff to/from this path.
        --diff TARGET_PATH           Compare configuration to this path. Use --file to specify the source file name, --path for the SOURCE_PATH, otherwise stdin is used.
    -s, --set KEY=VALUE              Set one key to value. Example: --set mysql/database=localhost
    -f, --fetch KEY                  Fetch the value for one setting. Example: --fetch mysql/database.
    -d, --delete KEY                 Delete one specific key.
    -r, --delete-tree PATH           Recursively delete all keys under the specified path.
    -c, --console                    Start interactive console.
        --provider PROVIDER          Provider to use. [ssm | file]. Default: ssm
        --provider-file FILE_NAME    For --provider file only. The config file to read and write. Default: $SECRET_CONFIG_FILE_NAME, then config/application.yml.
        --no-filter                  For --export only. Do not filter passwords and keys.
        --interpolate                For --export only. Evaluate string interpolation and __import__.
        --prune                      For --import only. During import delete all existing keys for which there is no key in the import file. Only works with --import.
        --force                      For --import only. Overwrite all values, not just the changed ones. Useful for changing the KMS key.
        --key_id KEY_ID              For --import only. Encrypt config settings with this AWS KMS key id. Default: AWS Default key.
        --key_alias KEY_ALIAS        For --import only. Encrypt config settings with this AWS KMS alias.
        --random_size INTEGER        Deprecated. For --import only. Default size in bytes to use when generating values when __generate__ is encountered in the source. Supply the size on each value instead, as __generate__:size. Default: 32
    -v, --version                    Display Secret Config version.
    -h, --help                       Prints this help.
~~~

### CLI Examples

#### Import from a file into SSM parameters

To get started it is useful to create a YAML file with all the relevant settings and then import
it into AWS SSM Parameter store. This file is the same as `applcation.yml` except that each file
is just for one environment. I.e. It does not contain the `test` or `development` root level entries.

For example: `production.yml`

~~~yaml
mysql:
  database:   secret_config_production
  username:   secret_config
  password:   secret_configrules
  host:       mysql_server.example.net

mongo:
  database:   secret_config_production
  primary:    mongo_primary.example.net:27017
  secondary:  mongo_secondary.example.net:27017

secrets:
  secret_key_base: somereallylongproductionstring
~~~

Import a yaml file, into a path in AWS SSM Parameter Store:

    secret-config --import /production/my_application --file production.yml

Import a yaml file, into a path in AWS SSM Parameter Store, using a custom KMS key to encrypt the values:

    secret-config --import /production/my_application --file production.yml --key_id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

Import a yaml file, into a path in AWS SSM Parameter Store, using a custom KMS key alias to encrypt the values:

    secret-config --import /production/my_application --file production.yml --key_alias my_key_alias

#### Diff

Before importing a new config file into the AWS SSM Parameter store, a diff can be performed to determine
what the differences are that will be applied when the import is run with the `--prune` option.

    secret-config --diff /production/my_application --file production.yml 

Key:

    + Adding a new key to the registry.
    - The key will be removed from the registry during the import if --prune is specified.
    * The value for that key will change during an import.

#### Export SSM parameters

In AWS SSM Parameter store it can be difficult to
Export the values from a specific path into a yaml or json file so that they are easier to read.

Export from a path in AWS SSM Parameter Store to a yaml file, where passwords are filtered:

    secret-config --export /production/my_application --file production.yml 

Export from a path in AWS SSM Parameter Store to a yaml file, _without_ filtering out passwords:

    secret-config --export /production/my_application --file production.yml --no-filter

Export from a path in AWS SSM Parameter Store to a json file, where passwords are filtered:

    secret-config --export /production/my_application --file production.json 

#### Working with a local file instead of AWS

Every command above also runs against a local YAML file, with `--provider file`. No AWS credentials
are needed, which makes it useful for inspecting or editing `config/application.yml` directly, and for
trying out an import before running it against SSM.

The file is the store, in the same way that the parameter tree is the store for SSM, so paths address
locations inside it. Point at the file with `--provider-file`; the default is the
`SECRET_CONFIG_FILE_NAME` environment variable, then `config/application.yml`.

Fetch, set and delete a single key:

    secret-config --provider file --fetch /test/my_application/mysql/host
    secret-config --provider file --set /test/my_application/mysql/host=localhost
    secret-config --provider file --delete /test/my_application/mysql/host

Diff a candidate file against what is already in the store:

    secret-config --provider file --provider-file config/application.yml --diff /test/my_application --file candidate.yml

Import into a file that does not exist yet, which creates it:

    secret-config --provider file --provider-file config/new_application.yml --import /production/my_application --file production.yml

Because both paths live inside one file, `--path` diffs or copies one environment onto another
without leaving the file:

    secret-config --provider file --diff /production/my_application --path /test/my_application

Writes rewrite the whole file from its parsed contents, so comments and formatting are not preserved.
A file containing ERB is refused rather than written, since rewriting it would replace the ERB with
whatever it evaluated to and silently turn a template into a literal. Edit those files directly.

#### Copy values between paths in AWS SSM parameter store

It can be useful to keep a "master" copy of the values for an environment or stack in a custom path
in AWS Parameter Store. Then for each stack or environment that is spun up, copy the "master" / "common" values
into the new path. Once copied the values specific to that path can be updated accordingly.

Import configuration from an existing path in AWS SSM Parameter Store into another:

    secret-config --import /tenant73/my_application --path /production/my_application 

#### Generating random passwords

In the multi-tenant example above, we may want to generate a secure random password for each tenant.
In the source file or registry, set the value to `__generate__`, this will ensure that during the `import`
that the destination will receive a secure random value.

    mysql:
      password: __generate__

The value must be exactly `__generate__`, ignoring any surrounding spaces.

Existing values are left alone, so re-running the import does not replace a password that was already
generated. This holds under `--force` as well: forcing an import re-writes every key so that it is
re-encrypted under a new KMS key, but it never regenerates a value that is already present.

By default the length of the generated value is 32 bytes. To change it, supply the size on the token
itself, which sets it for that key alone:

    mysql:
      password: __generate__        # 32 bytes
      api_key:  __generate__:64     # 64 bytes

Note that the size must be written tight against the colon. `__generate__: 64` is not valid YAML in a
value position, since YAML reads the `: ` as the start of a nested mapping.

A value that starts with `__generate__` but is not one of those two forms, such as `__generate__:abc`
or `__generate__:0`, raises an error rather than being imported as a literal string, on the grounds that
it is far more likely to be a typo than an intended value.

#### `__generate__` is not `${random}`

Both produce a random value, and they behave very differently:

* `__generate__` is materialized once, by the CLI, during an `--import`. The generated value is written
  to the registry and stays there.
* `${random}` is a [string interpolation](interpolation). It is evaluated by the application every time
  the registry is loaded or refreshed, so it produces a different value on every restart.

Use `__generate__` for anything that has to stay the same after it is generated, such as a database
password. `${random}` is only suitable for values that are genuinely disposable within a single process.

#### Deprecated: `$(random)` and `--random_size`

`__generate__` was previously spelled `$(random)`, which was too easily confused with the `${random}`
interpolation above. The old spelling still works, but it prints a deprecation warning on stderr and will
be removed in the next major release. It does not accept a per-key size.

`--random_size` is deprecated alongside it. It set the size for every generated value in the import, so
two keys needing different sizes meant two separate imports. `__generate__:size` replaces it and is set
per key. The flag still works and still sets the default for values written as a bare `__generate__`, but
warns when supplied.

Set `SECRET_CONFIG_SILENCE_DEPRECATIONS` to any value to suppress both warnings while migrating.

