---
layout: default
---

## Providers
{:.no_toc}

**Contents**

* TOC
{:toc}

A provider is where settings are actually stored. Two ship with the gem, and application code reads the
same way against either:

| Provider | Store | Typical use |
| --- | --- | --- |
| `:file` | A local YAML file | Development, test, and the CLI without AWS |
| `:ssm` | AWS SSM Parameter Store | Production, and anywhere secrets must be encrypted at rest |

Select one when the registry is built:

~~~ruby
SecretConfig.use(:file, path: "/development")
SecretConfig.use(:ssm, path: "/production/my_application")
~~~

Arguments other than `path:` and `interpolate:` are passed through to the provider, and are documented
per provider below. See [Configuration](config) for the rest of `use`.

## File provider

Reads and writes a single YAML file. It has no dependencies beyond the standard library, so it works
anywhere with no credentials and no network.

~~~ruby
SecretConfig.use(:file, path: "/development")
~~~

### Which file

The file is chosen in this order:

1. The `file_name:` argument.
2. The `SECRET_CONFIG_FILE_NAME` environment variable.
3. `config/application.yml`.

~~~ruby
SecretConfig.use(:file, path: "/development", file_name: "config/settings.yml")
~~~

A shared file is useful when several engines or internal gems live in one repository and should read the
same development settings:

~~~ruby
SecretConfig.use(:file, path: "/development", file_name: "../../../config/application.yml")
~~~

### Layout

The file is a nested hash. The registry's root path selects the subtree it starts from, so a file
holding several environments has one top-level key per environment:

~~~yaml
development:
  mysql:
    host: 127.0.0.1

test:
  mysql:
    host: 127.0.0.1
~~~

With `path: "/development"`, the key `mysql/host` reads `development.mysql.host`.

The path does not have to be one level deep. A file shared by several applications can nest them:

~~~yaml
development:
  my_application:
    mysql:
      host: 127.0.0.1
~~~

Read with `path: "/development/my_application"`.

### ERB

The file is passed through ERB before it is parsed, so values can be computed:

~~~yaml
development:
  mysql:
    host: <%= ENV.fetch("DB_HOST", "127.0.0.1") %>
~~~

This is evaluated every time the file is read, which includes every `refresh!`.

### Writing

The file provider is writable, so `set`, `[]=` and `delete` work against it, as do the corresponding
[command line](cli) operations.

Two things to know before writing to a file you care about:

* **The file is rewritten from its parsed contents.** Comments, key order and formatting are not
  preserved. What comes back is what YAML emits.
* **A file containing ERB is refused**, with a `ConfigurationError`, rather than written. Rewriting it
  would replace the ERB with whatever it evaluated to, silently turning a template into a literal.
  Edit those files directly.

The file does not have to exist before the provider is constructed; a write creates it, along with any
missing directories. Reads still raise `ConfigurationError` when it is missing, so
`SecretConfig.use(:file)` against a nonexistent file fails at startup exactly as before. This is what
lets `secret-config --import` bootstrap a new file from nothing.

### Errors

| Error | Cause |
| --- | --- |
| `ConfigurationError: Cannot find config file: ...` | The file does not exist, on a read |
| `ConfigurationError: Path /x/y not found in file: ...` | The file exists but has nothing at the root path |
| `ConfigurationError: Cannot write to config file containing ERB: ...` | A write was attempted against a template |

The second one is usually a mismatch between the root path and the file's top-level keys. Check both.

## SSM provider

Reads and writes AWS SSM Parameter Store. Every value is written as a `SecureString`, encrypted with a
KMS key, so nothing is stored in the clear.

~~~ruby
SecretConfig.use(:ssm, path: "/production/my_application")
~~~

### Installing

The AWS SDK is not a dependency of this gem, so that applications using the file provider do not pull it
in. Add it yourself:

~~~ruby
gem "aws-sdk-ssm"
~~~

Without it, constructing the provider raises
`LoadError: Install gem 'aws-sdk-ssm' to use AWS Parameter Store`.

### Options

| Option | Default | Purpose |
| --- | --- | --- |
| `key_id:` | `SECRET_CONFIG_KEY_ID`, then the account default `alias/aws/ssm` | KMS key id used when writing |
| `key_alias:` | `SECRET_CONFIG_KEY_ALIAS` | KMS key alias used when writing. Takes precedence over `key_id:`, and is prefixed with `alias/` if not already |
| `retry_count:` | `25` | Maximum retries when the Parameter Store throttles a read |
| `retry_max_ms:` | `10_000` | Upper bound in ms for the sleep between retries |

Any other option is passed straight to
[`Aws::SSM::Client`](https://docs.aws.amazon.com/sdkforruby/api/Aws/SSM/Client.html#initialize-instance_method),
which is how region, credentials and endpoints are set:

~~~ruby
SecretConfig.use(
  :ssm,
  path:        "/production/my_application",
  key_id:      "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  credentials: Aws::AssumeRoleCredentials.new(
    role_arn:          "arn:aws:iam::111111122222222:role/assume_role_name",
    role_session_name: "session-name-to-identify-#{SecureRandom.uuid}"
  )
)
~~~

The KMS key must exist before it is named here. Using a custom key rather than the account default is
what allows the key to be rotated on its own schedule, which is generally what a compliance regime is
asking for.

If [Semantic Logger](https://logger.reidmorrison.com/) is loaded, the AWS client logs through it.

### Retries and throttling

Parameter Store allows 40 `GetParametersByPath` calls per second on the standard tier. The whole
configuration is read at startup and on `refresh!`, so this is only reached when many processes start at
once, such as a fleet-wide restart.

When it is, the provider retries. Each retry sleeps a **random** interval between zero and
`retry_max_ms`, rather than backing off exponentially. That is deliberate: the servers hitting the limit
are all restarting together, and a random sleep spreads them out instead of having them retry in
lockstep.

The limit can be raised to 100 calls per second for an additional cost. See
[Parameter Store throughput](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-throughput.html).

### IAM policy

The application needs these actions:

~~~json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ssm:GetParametersByPath",
                "ssm:GetParameter",
                "ssm:PutParameter",
                "ssm:DeleteParameter"
            ],
            "Resource": "*"
        }
    ]
}
~~~

This grants only Parameter Store capabilities, not the rest of AWS Systems Manager. An application that
never writes needs only the two `Get` actions.

Narrow `Resource` to the paths the application actually uses when you can. `"*"` is shown here because
the right ARN depends on your account and region.

These are not used by Secret Config, but are worth granting to anyone managing parameters through the
AWS Console:

* `ssm:DescribeParameters`
* `ssm:GetParameterHistory`
* `ssm:GetParameters`

### Limits and cost

Parameter Store is inexpensive, often free, within these limits:

* **Values under 4KB**: up to 10,000 parameters per AWS region, on the free standard tier. Confirm
  current [AWS SSM pricing](https://aws.amazon.com/systems-manager/pricing/) for your account.
* **Values between 4KB and 8KB**: charged, because they require the advanced tier. See
  [parameter tiers](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-default-tier.html).
* **Maximum value size is 8KB.** See [SSM limits](https://docs.aws.amazon.com/general/latest/gr/ssm.html).
* **40 `GetParametersByPath` calls per second**, as covered above.

A custom KMS key costs about $1 per month. By comparison, AWS Secrets Manager charges per secret per
month, which at the granularity of an application's entire configuration adds up quickly.

## Writing a provider

A provider implements four methods, and inherits from `Providers::Provider`:

~~~ruby
module SecretConfig
  module Providers
    class MyProvider < Provider
      # Yields every key under `path`, with its **absolute** key and string value.
      def each(path)
        # yield("/production/my_application/mysql/host", "db.example.net")
      end

      # Returns the value for one absolute key, or nil when missing.
      def fetch(key)
      end

      # Writes one absolute key.
      def set(key, value)
      end

      # Removes one absolute key. Deleting a missing key is not an error.
      def delete(key)
      end
    end
  end
end
~~~

Providers deal in **absolute** keys. The registry strips its root path before caching, so everything
above the provider works in relative keys. `fetch` is used to resolve an absolute
[`__import__`](interpolation); `each` is what the registry calls on load and refresh.

Register it in the `autoload` list in `lib/secret_config.rb`, after which `:my_provider` resolves to
`SecretConfig::Providers::MyProvider`:

~~~ruby
SecretConfig.use(:my_provider, path: "/production/my_application")
~~~

An instance can also be passed directly, which avoids registering it at all:

~~~ruby
SecretConfig.use(MyProvider.new, path: "/production/my_application")
~~~

If the provider needs an optional gem, require it inside a `begin`/`rescue LoadError` that re-raises
with an install hint, the way the SSM provider does. That turns a missing dependency into a sentence
telling the reader what to install.

## Next steps

* [Configuration](config): the rest of `SecretConfig.use`.
* [Command Line](cli): importing into and exporting from either provider.
* [Rails](rails): choosing a provider per environment.
