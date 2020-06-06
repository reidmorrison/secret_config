---
layout: default
---

# Secret Config

Securely store and share secrets and configuration settings centrally.

Examples of some of the many values that can be securely managed by Secret Config:
* Database usernames
* Passwords
* Connection pool sizes
* Hostnames
* Connection timeouts
* Encryption keys and certificates

## Features

Supports storing configuration information in:
* File
    * For development and testing use.
* Environment Variables
    * Environment Variables take precedence and can be used to override any setting.
* AWS System Manager Parameter Store
    * Encrypt and securely store secrets such as passwords centrally.

Since all values are stored as strings in the central directory or config file, 
the following type conversions are supported:
* `integer`
* `float`
* `string`
* `boolean`
* `symbol`
* `json`
* `array`

Supported conversions:
* `base64`

## Benefits

Benefits of moving sensitive configuration information into AWS System Manager Parameter Store:

  * Supports a hierarchical key structure.
  * Supports thousands of individual settings in a single application.
  * Securely stores sensitive settings or encryption keys in encrypted form in the AWS SSM Parameter Store.   
  * To meet PCI Compliance the KMS encryption key can be transparently rotated without impacting secured values.  
  * Removes security concerns with placing passwords or encryption keys in the clear in environment variables.
  * Very low cost, if not entirely free for thousands of settings. 
    * AWS System Manager Parameter Store does not charge for parameters.
    * Still recommend using a custom KMS key that charges only $1 per month.
    * Amounts as of 4/2019. Confirm what AWS charges you for these services.
  * AWS Secrets Manager charges for every secret being managed, which can accumulate quickly with large projects.
  * Configure multiple distinct application instances to support multiple tenants.
    * For example, use separate databases with unique credentials for each tenant.
  * Separation of responsibilities is achieved since operations can manage production configuration.
    * Developers do not need to be involved with production configuration such as host names and passwords.
  * All values are encrypted by default when stored in the AWS Parameter Store.
    * Prevents accidentally not encrypting sensitive data.

## Introduction

When Secret Config starts up it reads all configuration entries into memory for all keys under the configured path.
This means that once Secret Config has initialized all calls to Secret Config are extremely fast.

The in-memory copy of the registry can be refreshed at any time by calling `SecretConfig.refresh!`. It can be refreshed
via a process signal, or by calling it through an event, or via a messaging system.

It is suggested that any programmatic lookup to values stored in Secret Config are called every time a value is
being used, rather than creating a local copy of the value. This ensures that a refresh of the registry will take effect
immediately for any code reading from Secret Config.

## Limitations

AWS SSM Parameter Store is a very cost effective and often completely free solution with the following limitations:

* For settings where the value is less than 4KB in size:
    * Upto 10,000 settings per AWS region.
    * Usually Free.
        * Confirm [AWS SSM pricing](https://aws.amazon.com/systems-manager/pricing/) for your AWS account. 
* For settings where the value is between 4KB and 8KB in size:
    * There is an additional AWS cost for each of these settings since it has to be stored in the Advanced tier.
    * See: [AWS SSM Parameter Store Parameter Tier](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-default-tier.html)
* The maximum size for the value of any setting cannot exceed 8KB.
    * See: [AWS SSM Limitations](https://docs.aws.amazon.com/general/latest/gr/ssm.html)
* Includes up to 40 `GetParametersByPath` calls per second.
    * The standard limit is ample for most scenarios, since the configuration is only read on 
      startup and whenever `SecretConfig.refresh!` is called from within the application.
    * An automated retry is built into Secret Config to retry with exponential backoffs when this limit is reached.
    * This limit can be increased to 100 GetParametersByPath calls per second for an additional cost.
        * See: [AWS SSM Parameter Store throughput](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-throughput.html)

## Next Steps

Checkout the [Secret Config API](api).
