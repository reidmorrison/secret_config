# Secret Config
[![Gem Version](https://img.shields.io/gem/v/secret_config.svg)](https://rubygems.org/gems/secret_config) [![Build Status](https://travis-ci.org/rocketjob/secret_config.svg?branch=master)](https://travis-ci.org/rocketjob/secret_config) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Gitter chat](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Centralized Configuration and Secrets Management for Ruby and Rails applications.

Securely store configuration information centrally, supporting multiple tenants of the same application.

Checkout https://config.rocketjob.io/

## Documentation

* [Guide](https://config.rocketjob.io/)

## Support

* Questions? Join the chat room on Gitter for [rocketjob support](https://gitter.im/rocketjob/support)
* [Report bugs](https://github.com/rocketjob/secret_config/issues)

## v0.10 Upgrade Notes

String interpolation has been changed to use `$` instead of `%`. Please change
all interpolated strings to use `$` before upgrading.

Example: `%{date}` needs to be changed to `${date}`

## v0.9 Upgrade Notes

Note that the command line program name has changed from `secret_config` to `secret-config`. 
Be careful that the arguments have also changed. The arguments are now consistent across operations.
The command line examples below have also been updated to reflect the changes. 
 
Please run `secret-config --help` to see the new arguments and updated operations.  

## Versioning

This project adheres to [Semantic Versioning](https://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison)

## License

Copyright 2020 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
