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
        --no-filter                  For --export only. Do not filter passwords and keys.
        --interpolate                For --export only. Evaluate string interpolation and __import__.
        --prune                      For --import only. During import delete all existing keys for which there is no key in the import file. Only works with --import.
        --force                      For --import only. Overwrite all values, not just the changed ones. Useful for changing the KMS key.
        --key_id KEY_ID              For --import only. Encrypt config settings with this AWS KMS key id. Default: AWS Default key.
        --key_alias KEY_ALIAS        For --import only. Encrypt config settings with this AWS KMS alias.
        --random_size INTEGER        For --import only. Size to use when generating random values when $(random) is encountered in the source. Default: 32
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

#### Copy values between paths in AWS SSM parameter store

It can be useful to keep a "master" copy of the values for an environment or stack in a custom path
in AWS Parameter Store. Then for each stack or environment that is spun up, copy the "master" / "common" values
into the new path. Once copied the values specific to that path can be updated accordingly.

Import configuration from an existing path in AWS SSM Parameter Store into another:

    secret-config --import /tenant73/my_application --path /production/my_application 

#### Generating random passwords

In the multi-tenant example above, we may want to generate a secure random password for each tenant.
In the source file or registry, set the value to `$random`, this will ensure that during the `import`
that the destination will receive a secure random value.

By default the length of the randomized value is 32 bytes, use `--random_size` to adjust the length of
the randomized string.

