---
layout: default
---

# API

When Secret Config starts up it reads all configuration entries immediately for all keys under the configured path.
This means that once Secret Config has been initialized all calls to Secret Config are extremely fast.

Secret Config supports the following programmatic interface:

## Read values

Fetch the value for the supplied key, returning nil if not found:

~~~ruby
# Key is present:
SecretConfig["logger/level"]
# => "info"

# Key is missing:
SecretConfig["logger/blah"]
# => nil
~~~

Fetch the value for the supplied key, raising `SecretConfig::MissingMandatoryKey` if not found:

~~~ruby
# Key is present:
SecretConfig.fetch("logger/level")
# => "info"

# Key is missing:
SecretConfig.fetch("logger/blah")
# => SecretConfig::MissingMandatoryKey (Missing configuration value for /development/logger/blah)
~~~

A default value can be supplied when the key is not found in the registry:

~~~ruby
SecretConfig.fetch("logger/level", default: "info")
# => "info"
~~~

Since AWS SSM Parameter store and environment variables only support string values,
it is neccessary to convert the string back to the type required by the program.

The following types are supported:
    `:integer`
    `:float`
    `:string`
    `:boolean`
    `:symbol`
    `:json`

~~~ruby
# Without type conversion:
SecretConfig.fetch("symmetric_encryption/version")
# => "0"

# With type conversion:
SecretConfig.fetch("symmetric_encryption/version", type: :integer)
# => 0
~~~

Sometimes it is useful to store arrays of values as a single key.  

~~~ruby
# Example: A list of host names could be stored as: "primary.example.net,secondary.example.net,backup.example.net"
# To extract it as an array of strings: 
SecretConfig.fetch("address_services/hostnames", separator: ",")
# => ["primary.example.net", "secondary.example.net", "backup.example.net"]

# Example: A list of ports could be stored as: "12345,5343,26815"
# To extract it as an array of Integers: 
SecretConfig.fetch("address_services/ports", type: :integer, separator: ",")
# => [12345, 5343, 26815]
~~~

When storing binary data, it should be encoded with strict base64 encoding. To automatically convert it back to binary
specify the encoding as `:base64`

~~~ruby
# Return a value that was stored in Base64 encoding format:
SecretConfig.fetch("symmetric_encryption/iv")
# => "FW+/wLubAYM+ZU0bWQj59Q=="

# Base64 decode a value that was stored in Base64 encoding format:
SecretConfig.fetch("symmetric_encryption/iv", encoding: :base64)
# => "\x15o\xBF\xC0\xBB\x9B\x01\x83>eM\eY\b\xF9\xF5"
~~~

## Key presence

Returns whether a key is present in the registry:

~~~ruby
SecretConfig.key?("logger/level")
# => true
~~~

## Write values

When Secret Config is configured to use the AWS SSM Parameter store, its values can be modified:

~~~ruby
SecretConfig["logger/level"] = "debug"
~~~

~~~ruby
SecretConfig.set("logger/level", "debug")
~~~

## Configuration

Returns a Hash copy of the configuration as a tree:

~~~ruby
SecretConfig.configuration
~~~

## Refresh Configuration

Tell Secret Config to refresh its in-memory copy of the configuration settings.

~~~ruby
SecretConfig.refresh!
~~~

Example, refresh the registry any time a SIGUSR2 is raised, add the following code on startup:

~~~ruby
Signal.trap('USR2') do
  SecretConfig.refresh!
end
~~~

Then to make the process refresh it registry:
~~~shell
kill -SIGUSR2 1234
~~~

Where `1234` above is the process PID.

## Next Steps

Checkout the [Secret Config Guide](guide).

