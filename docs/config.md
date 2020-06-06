---
layout: default
---

## Configuration

Out of the box Secret Config will look in the local file system for the file `config/application.yml`
as covered in the [Guide](guide). By default it will use env var `RAILS_ENV` to determine which environment settings to load.

Add the following lines to the very top of `application.rb` under the line `class Application < Rails::Application`:

~~~ruby
module MyApp
  class Application < Rails::Application

    # Add the following lines to configure Secret Config:
    if Rails.env.development? || Rails.env.test?
      # Use 'config/application.yml'
      config.secret_config.use :file
    else
      # Read configuration from AWS SSM Parameter Store
      config.secret_config.use :ssm, path: "/#{Rails.env}/my_app"
    end

    # ....
  end
end
~~~

`path` is the path from which the configuration data will be read. This path uniquely identifies the
configuration for this instance of the application. In the example above it uses the rails env and application name
by default. The `path` set here can be overridden using the `SECRET_CONFIG_PATH` environment variable.

By placing the secret config configuration as the very first configuration item, it allows any subsequent
configuration item to access the centralized configuration in AWS System Manager Parameter Store.

The environment variable `SECRET_CONFIG_PROVIDER` can also be used to override the provider.
For example:
    `export SECRET_CONFIG_PROVIDER=ssm`
Or,
    `export SECRET_CONFIG_PROVIDER=file`

If we need 2 completely separate instances of the application running in a single AWS account then we could use
multiple paths. For example:

    /production1/my_application
    /production2/my_application

    /production/instance1/my_application
    /production/instance2/my_application

The `path` is completely flexible, but must be unique for every AWS account under which the application will run.
The same `path` can be used in different AWS accounts though. It is also not replicated across regions.

When writing settings to the parameter store, it is recommended to use a custom KMS key to encrypt the values,
if you don't specify a key ID, the system uses the default key associated with your AWS account `alias/aws/ssm`.
To supply the key to encrypt the values with, add the `key_id`, or `key_alias` parameter:

~~~ruby
module MyApp
  class Application < Rails::Application

    # Add the following lines to configure Secret Config:
    if Rails.env.development? || Rails.env.test?
      # Use 'config/application.yml'
      config.secret_config.use :file
    else
      # Read configuration from AWS SSM Parameter Store
      config.secret_config.use :ssm,
        path: "/#{Rails.env}/my_app",
        key_id: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    end

    # ....
  end
end
~~~

Note: The relevant KMS key must be created first prior to using it here.

`ssm` provider supports various configuration parameters that can be provided as keyword arguments 
for `config.secret_config.use :ssm, path, **args`

Args hash:
* **:key_id** (String) - Key id of the KMS key to use when writing setting to the AWS Parameter store. Can be overriden with environment variable `SECRET_CONFIG_KEY_ID`.
* **:key_alias** (String) - Alias of the KMS key to use when writing setting to the AWS Parameter store. Can be overriden with environment variable `SECRET_CONFIG_KEY_ALIAS`.
* **:retry_count** (Integer, default=10) - Max number of retries when reading AWS SSM Parameter Store entries.
* **:retry_max_ms** (Integer, default=3_000) - Interval in ms between retries, `sleep` is used to facilitate throttling.
* any options suported by [Aws::SSM::Client](https://docs.aws.amazon.com/sdkforruby/api/Aws/SSM/Client.html#initialize-instance_method) 
For example, explicitly set **:credentials**:
~~~ruby
  config.secret_config.use :ssm,
    path: "/#{Rails.env}/my_app",
    key_id: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
    credentials: Aws::AssumeRoleCredentials.new(
      role_arn:          "arn:aws:iam::111111122222222:role/assume_role_name",
      role_session_name: "session-name-to-identify-#{SecureRandom.uuid}"
    ))
~~~

### Secret Config Environment variables

Priority describes when an environment variable is used as a default value, preceds configuration value or overrides.

 Name                      | Desctiption                                                     | Priority
 ------------------------- | --------------------------------------------------------------- | --------
 `SECRET_CONFIG_PATH`      | path from which the configuration data will be read             | precede
 `SECRET_CONFIG_PROVIDER`  | override the provider configured for `config.secret_config.use` | override
 `SECRET_CONFIG_KEY_ID`    | encryption `key_id`                                             | default
 `SECRET_CONFIG_KEY_ALIAS` | encryption `key_alias`                                          | default
 `SECRET_CONFIG_ACCOUNT_ID`| used in `rspec` to configure AWS Account Id for role assuming   | required

### Shared configuration for development and test

When running multiple engines or private "gems" inside the same code repository, the development and test
configuration file `application.yml` can be shared. Update the lines above to:

~~~ruby
module MyApp
  class Application < Rails::Application

    # Add the following lines:
    if Rails.env.development? || Rails.env.test?
      # Use 'config/application.yml'
      config.secret_config.use :file, file_name: "../../../config/application.yml"
    else
      # Read configuration from AWS SSM Parameter Store
      config.secret_config.use :ssm, path: "/#{Rails.env}/my_app"
    end

    # ....
  end
end
~~~

Where `file_name` is the full path and filename to where the shared `application.yml` is located.

### Authorization

The following policy needs to be added to the IAM Group under which the application will be running:

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
                "ssm:DeleteParameter",
            ],
            "Resource": "*"
        }
    ]
}
~~~

The above policy restricts read and write access to just the Parameter Store capabilities of AWS System Manager.

These additional Actions are not used by Secret Config, but may be useful for anyone using the AWS Console directly
to view and modify parameters:
- `ssm:DescribeParameters`
- `ssm:GetParameterHistory`
- `ssm:GetParameters`

## Docker

Secret Config is at its best when the application is containerized. By externalizing the configuration the same
docker container can be tested in one or more environments and then deployed directly to production without
any changes. The only difference being the path that container uses to read its configuration from.

Another important benefit is that the docker image does not contain any production or test credentials since
these are all stored in AWS SSM Parameter Store.

When a Ruby / Rails application is using Secret Config for its configuration settings, it only requires the
following environment variables when starting up the container in for example AWS ECS or AWS Fargate:

~~~shell
export SECRET_CONFIG_PATH=/production/my_application
~~~

For rails applications, typically the `RAILS_ENV` is also needed, but not required for Secret Config.

~~~shell
export RAILS_ENV=production
~~~

### Logging

When using Semantic Logger, the following code could be added to `application.rb` to facilitate configuration
of the logging output via Secret Config:

~~~ruby
# Logging
config.log_level                       = config.secret_config.fetch("logger/level", default: :info, type: :symbol)
config.semantic_logger.backtrace_level = config.secret_config.fetch("logger/backtrace_level", default: :error, type: :symbol)
config.semantic_logger.application     = config.secret_config.fetch("logger/application", default: "my_app")
config.semantic_logger.environment     = config.secret_config.fetch("logger/environment", default: Rails.env)
~~~

In any environment the log level can be changed, for example set `logger/level` to `debug`. And it can be changed
in the AWS SSM Parameter Store, or directly with the environment variable `export LOGGER_LEVEL=debug`

`logger/environment` can be used to identify which tenant the log messages are emanating from. By default it is just
the rails environment. For example set `logger/environment` to `tenant73`.

Additionally the following code can be used with containers to send log output to standard out:

~~~ruby
destination = config.secret_config.fetch("logger/destination", default: :file, type: :symbol)
if destination == :stdout
  STDOUT.sync                                    = true
  config.rails_semantic_logger.add_file_appender = false
  config.semantic_logger.add_appender(
    io:        STDOUT,
    level:     config.log_level,
    formatter: config.secret_config.fetch("logger/formatter", default: :default, type: :symbol)
  )
end
~~~

Specifically for docker containers it is necessary to turn off file logging and turn on logging to standard out
so that AWS Cloud Watch can pick up the log data.

To start with `logger/destination` of `stdout` will work with regular non-colorized output. When feeding the
log output into something that can process JSON, set `logger/formatter` to `json`.

The benefit with the above approach is that a developer can pull the exact same container image that is running
in production and configure it to run locally on their laptop. For example, set `logger/destination` to `file`.

The above code can be modified as necessary to add any Semantic Logger appender to write directly to external
centralized logging systems, instead of writing to standard out or local files.

### Email Server and Assets

An example of how to setup the email server and the assets for html emails. Add to `application.rb`:

~~~ruby
# Emails
application_url = config.secret_config.fetch("emails/asset_host")
uri             = URI.parse(application_url)

config.action_mailer.default_url_options   = {host: uri.host, protocol: uri.scheme}
config.action_mailer.asset_host            = application_url
config.action_mailer.smtp_settings         = {address: config.secret_config.fetch("emails/smtp/address", default: "localhost")}
config.action_mailer.raise_delivery_errors = config.secret_config.fetch("emails/raise_delivery_errors", default: true, type: :boolean)
~~~

### Symmetric Encryption

An example of how to setup Symmetric Encryption. Add to `application.rb`:

~~~ruby
# Encryption
config.symmetric_encryption.cipher =
  SymmetricEncryption::Cipher.new(
    key:     config.secret_config.fetch('symmetric_encryption/key', encoding: :base64),
    iv:      config.secret_config.fetch('symmetric_encryption/iv', encoding: :base64),
    version: config.secret_config.fetch('symmetric_encryption/version', type: :integer),
  )

# Also support one prior encryption key version during key rotation
if config.secret_config.key?('symmetric_encryption/old/key')
  SymmetricEncryption.secondary_ciphers = [
    SymmetricEncryption::Cipher.new(
      key:     config.secret_config.fetch('symmetric_encryption/old/key', encoding: :base64),
      iv:      config.secret_config.fetch('symmetric_encryption/old/iv', encoding: :base64),
      version: config.secret_config.fetch('symmetric_encryption/old/version', type: :integer),
    ),
  ]
end
~~~

Using this approach the file `config/symmetric-encryption.yml` can be removed once the keys have been moved to
the registry.

To extract existing keys from the config file so that they can be imported into the registry,
run the code below inside a console in each of the respective environments.

~~~ruby
require "yaml"
require "base64"

def se_config(cipher)
  {
    "key"     => Base64.strict_encode64(cipher.send(:key)),
    "iv"      => Base64.strict_encode64(cipher.iv),
    "version" => cipher.version
  }
end

config = { "symmetric_encryption" => se_config(SymmetricEncryption.cipher) }
if cipher = SymmetricEncryption.secondary_ciphers.first
  config["symmetric_encryption"]["old"] = se_config(cipher)
end
puts config.to_yaml
~~~

