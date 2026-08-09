# Secret Config
[![Gem Version](https://img.shields.io/gem/v/secret_config.svg)](https://rubygems.org/gems/secret_config) [![Build Status](https://github.com/reidmorrison/secret_config/workflows/build/badge.svg)](https://github.com/reidmorrison/secret_config/actions?query=workflow%3Abuild) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg)

Ship the same image to every environment and tenant. Configuration and secrets come from one central store.

Centralized configuration and secrets management for Ruby and Rails. Settings are read from AWS SSM
Parameter Store, AWS Secrets Manager, or a local file during development and test, and can be
overridden with environment variables.

## Documentation

* [Secret Config](https://config.reidmorrison.com/)
    * [Getting Started](https://config.reidmorrison.com/guide.html)
    * [Guide](https://config.reidmorrison.com/api.html)
    * [Command Line](https://config.reidmorrison.com/cli.html)
    * [Rails](https://config.reidmorrison.com/rails.html)

## Upgrading

See [Upgrading](https://config.reidmorrison.com/upgrading.html) for the breaking changes in each major
release, and [CHANGELOG.md](CHANGELOG.md) for the complete record.

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
