---
layout: default
---

## Providers
{:.no_toc}

**Contents**

* TOC
{:toc}

A provider is where settings are actually stored. Three ship with the gem, and application code reads
the same way against any of them:

| Provider | Store | Typical use |
| --- | --- | --- |
| `:file` | A local YAML file | Development, test, and the CLI without AWS |
| `:ssm` | AWS SSM Parameter Store | Production, and anywhere secrets must be encrypted at rest |
| `:secrets_manager` | AWS Secrets Manager | Production, where rotation or per-secret audit logging is required. **Beta** |

Select one when the registry is built:

~~~ruby
SecretConfig.use(:file, path: "/development")
SecretConfig.use(:ssm, path: "/production/my_application")
SecretConfig.use(:secrets_manager, path: "/production/my_application")
~~~

`:ssm` and `:secrets_manager` are interchangeable: both hold one setting per key under a path, so the
same tree can be moved between them with the [command line](cli). They differ in cost, which is covered
below, and in how a delete behaves.

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

### Permissions

The file holds settings in the clear, so a file created by a write is given mode `0600`, readable only
by the user that owns it. The default umask on most systems would otherwise create it readable by every
user on the machine.

A file that already exists keeps the mode it has, since it may have been widened deliberately. When a
write finds one that other users can read, it prints a warning naming the file. To settle it:

    chmod 600 config/application.yml

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
the right ARN depends on your account and region. That narrowing is worth the effort: `PutParameter` on
a path is a stronger permission than it looks, because a setting written there can read the process
environment of everything that loads it through `${env:...}`, and can read other paths through an
absolute `__import__`. See
[Interpolation](interpolation#what-the-store-is-trusted-to-do).

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

## Secrets Manager provider

**This provider is beta, and feedback is wanted.** It is complete and tested, but it has not yet had
the production mileage the other two have, and one design decision in particular is worth hearing about
before it settles: whether one secret per setting is the right layout, given that Secrets Manager users
often keep many related values in a single JSON document. If you are using it, please say so on
[issue 8](https://github.com/reidmorrison/secret_config/issues/8), along with anything that did not
behave the way the Parameter Store provider would have.

Reads and writes AWS Secrets Manager. One secret holds one setting, laid out under a path exactly as
the Parameter Store tree is, so the two providers are interchangeable.

~~~ruby
SecretConfig.use(:secrets_manager, path: "/production/my_application")
~~~

Choose this over the Parameter Store when you need built-in rotation or per-secret access audit
logging. It costs meaningfully more, so read [Limits and cost](#limits-and-cost-1) before pointing an
entire configuration tree at it.

### Installing

The AWS SDK is not a dependency of this gem. Add it yourself:

~~~ruby
gem "aws-sdk-secretsmanager"
~~~

Without it, constructing the provider raises
`LoadError: Install gem 'aws-sdk-secretsmanager' to use AWS Secrets Manager`.

### Options

| Option | Default | Purpose |
| --- | --- | --- |
| `key_id:` | `SECRET_CONFIG_KEY_ID`, then the account default `aws/secretsmanager` | KMS key id used when writing |
| `key_alias:` | `SECRET_CONFIG_KEY_ALIAS` | KMS key alias used when writing. Takes precedence over `key_id:`, and is prefixed with `alias/` if not already |
| `recovery_window_in_days:` | `30` | How long a deleted secret can still be restored. Must be between 7 and 30 |

Any other option is passed straight to
[`Aws::SecretsManager::Client`](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SecretsManager/Client.html#initialize-instance_method),
which is how region, credentials and endpoints are set.

If [Semantic Logger](https://logger.reidmorrison.com/) is loaded, the AWS client logs through it.

### How settings are loaded

The whole tree is read once, when the registry is built, and again on every `SecretConfig.refresh!`.
Between those, every lookup is an in-memory hash read that makes no API call. This is the same
behaviour as the other two providers, and it is worth being explicit about here because Secrets
Manager bills per API call and logs every read.

The Parameter Store has `get_parameters_by_path`, which walks a hierarchy directly. Secrets Manager has
no hierarchical listing, so the load works differently:

1. `batch_get_secret_value` is called with a `name` filter set to the registry's root path. That
   returns names and values together, so there is no separate listing pass.
2. AWS matches that filter as a **plain string prefix**, case-sensitive, which knows nothing about `/`
   as a separator. A root path of `/production/my_app` therefore also matches secrets named
   `/production/my_application/mysql/host`. The provider discards anything that is not under the root
   path as a directory, so the registry sees exactly the keys it would have seen from the Parameter
   Store.
3. Results arrive 20 at a time, which is the maximum Secrets Manager allows, and the provider follows
   the pagination token until the last page. A tree of 200 settings is 10 calls per process at
   startup.

Three consequences worth knowing:

* **A rotated secret is not picked up until `refresh!` or a restart.** Rotation changes the value in
  AWS, not in the running process. If you rotate on a schedule, call `SecretConfig.refresh!` on one of
  its own, or restart. This is not specific to rotation, it is how the in-memory cache has always
  worked, but rotation is the case where it surprises people.
* **A secret that cannot be read fails the load.** `batch_get_secret_value` reports a per-secret
  failure, such as an `AccessDeniedException` on one key, in an `errors` array alongside a successful
  response for the rest. Rather than starting up with a configuration that is quietly missing
  settings, the provider raises `ConfigurationError` naming the secrets that failed.
* **Binary secrets are skipped.** Secret Config deals in strings. A secret stored as `SecretBinary`
  has no string value, so it is passed over rather than being loaded as an empty setting.

Each secret read produces a CloudTrail `GetSecretValue` entry, including when it is read as part of a
batch. A fleet of 50 processes restarting against 200 settings writes 10,000 entries.

### Writing

`set`, `[]=` and `delete` work, as do the corresponding [command line](cli) operations.

A write updates the secret if it exists and creates it otherwise, always under this provider's KMS key.
Every write creates a new version. Secrets Manager keeps 100 versions per secret and does not reclaim
any that are less than a day old, so avoid writing the same key repeatedly in a loop. Importing a tree,
where each key is written once, is unaffected.

### Deleting

This is the one place the two AWS providers genuinely differ. `delete_parameter` takes effect
immediately. Secrets Manager instead **schedules** the deletion:

* The secret stops being readable and drops out of the registry straight away.
* The name stays reserved for `recovery_window_in_days`, 30 by default, during which `restore_secret`
  can undo the deletion.
* Until that window elapses, writing the same key again fails.

The provider does not offer `ForceDeleteWithoutRecovery`. Discarding the recovery window throws away
the safety net that is a large part of why a store like this is chosen, and it does not make the name
reusable immediately in any case, since the permanent delete still happens asynchronously.

The practical effect is that `secret-config --delete-tree` followed by `--import` of the same path does
not work here the way it does against the Parameter Store. Import over the existing tree instead, with
`--prune` if keys need removing, and treat deletes as rare.

### Naming

Secret names may contain ASCII letters, numbers and `/_+=.@-`, up to 512 characters. Two things to
avoid in keys:

* **Do not end a key with a hyphen followed by exactly six characters.** Secrets Manager appends a
  hyphen and six random characters to build the ARN, and a name shaped that way is ambiguous when a
  secret is looked up by partial ARN.
* Characters outside that set, `:` for instance, are rejected by AWS even though the Parameter Store
  accepts some of them.

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
                "secretsmanager:BatchGetSecretValue",
                "secretsmanager:ListSecrets",
                "secretsmanager:GetSecretValue",
                "secretsmanager:CreateSecret",
                "secretsmanager:UpdateSecret",
                "secretsmanager:DeleteSecret"
            ],
            "Resource": "*"
        }
    ]
}
~~~

`ListSecrets` is required because the load filters by name, even though the provider never calls
`ListSecrets` itself. An application that never writes needs only the first three actions.

When the secrets are encrypted with a customer managed KMS key rather than `aws/secretsmanager`, the
application also needs `kms:Decrypt` on that key, and `kms:GenerateDataKey` as well if it writes.

`ListSecrets` cannot be narrowed by resource, so it has to be granted against `"*"`. Narrow the others
to the paths the application actually uses when you can.

### Limits and cost

Secrets Manager is not free, and one secret per setting is the granularity that makes that add up:

* **$0.40 per secret per month.** An application with 200 settings costs about $80 a month, where the
  Parameter Store standard tier is free. Confirm current
  [AWS Secrets Manager pricing](https://aws.amazon.com/secrets-manager/pricing/) for your account.
* **$0.05 per 10,000 API calls.** Negligible in comparison, since the tree is read once per process
  rather than per lookup.
* **Maximum value size is 64KB**, against 8KB for the Parameter Store, and 4KB before that store moves
  into its paid tier.
* **500,000 secrets per region**, and 100 versions per secret.

Rate limits are high enough not to need managing: 100 `BatchGetSecretValue` calls per second and
10,000 `GetSecretValue` calls per second, per region. That is why this provider has no retry loop of
the kind the SSM provider needs for its 40 calls per second. The AWS SDK's own retry handling covers
the occasional throttle.

### Choosing between the two AWS providers

Use the Parameter Store for an application's configuration tree, and reach for Secrets Manager when
something about the individual secret demands it:

| | Parameter Store | Secrets Manager |
| --- | --- | --- |
| Cost | Free up to 10,000 standard parameters | $0.40 per secret per month |
| Rotation | Build it yourself | Built in, with managed rotation for some AWS services |
| Audit | CloudTrail on the API call | CloudTrail per secret read |
| Delete | Immediate | Scheduled, 7 to 30 day recovery window |
| Value size | 8KB, 4KB before the paid tier | 64KB |

Both encrypt at rest with a KMS key you choose.

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
