---
layout: default
---

## String Interpolation

Values supplied for config settings can be replaced inline with date, time, hostname, pid and random values.

For example to include the `hostname` in the log file name setting:

~~~yaml
development:
  logger:
    level:     info
    file_name: /var/log/my_application_${hostname}.log
~~~

Available interpolations:

* ${date}
    * Current date in the format of "%Y%m%d" (CCYYMMDD)
* ${date:format}
    * Current date in the supplied format. See strftime
* ${time}
    * Current date and time down to ms in the format of "%Y%m%d%Y%H%M%S%L" (CCYYMMDDHHMMSSmmm)
* ${time:format}
    * Current date and time in the supplied format. See strftime
* ${env:name}
    * Extract value from the named environment variable.
    * Raises `SecretConfig::MissingEnvironmentVariable` when the environment variable is not defined.
* ${env:name,default}
    * Extract value from the named environment variable.
    * Returns the supplied default value when the environment variable is not defined.
    * Default values is stripped of leading and trailing spaces.
    * Default value must not include include `,`.
* ${hostname}
    * Full name of this host.
* ${hostname:short}
    * Short name of this host. Everything up to the first period.
* ${pid}
    * Process Id for this process.
* ${random}
    * URL safe Random 32 byte value.
* ${random:size}
    * URL safe Random value of `size` bytes.
* ${select:a,b,c,d}
    * Randomly select one of the supplied values. A new new value is selected on restart or refresh.
    * Values are separated by `,` and cannot include `,` in their values.
    * Values are stripped of leading and trailing spaces. 

#### Notes:

* To prevent interpolation use $${...}
* $$ is not touched, only ${...} is searched for.
* Since these interpolations are only evaluated at load time and
  every time the registry is refreshed there is no runtime overhead when keys are fetched.
