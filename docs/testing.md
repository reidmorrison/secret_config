---
layout: default
---

## Testing
{:.no_toc}

**Contents**

* TOC
{:toc}

Tests need two things from Secret Config: settings that are the same on every machine and in CI, and a
way to change one setting for one test without disturbing the others.

Both are covered here. Nothing on this page needs AWS.

## Step 1: Give the test suite its own settings

Add a `test` section to `config/application.yml`, alongside `development`:

~~~yaml
development:
  mysql:
    host:     127.0.0.1
    database: my_application_development

test:
  mysql:
    host:     127.0.0.1
    database: my_application_test
~~~

Because the file is checked into source control, every developer and CI read the same values. There are
no test credentials to distribute and nothing to set up on a new machine.

In Rails this is already wired up by the `application.rb` block from the [Rails guide](rails), which
uses the file provider for both `development` and `test` and picks the section from `Rails.env`.

Outside Rails, point at it in your test helper:

~~~ruby
require "secret_config"

SecretConfig.use(:file, path: "/test")
~~~

## Step 2: Override one setting for one test

The simplest override is an environment variable, since it needs no knowledge of Secret Config at all:

~~~ruby
def test_connects_to_the_replica
  ENV["MYSQL_HOST"] = "replica.example.net"
  SecretConfig.refresh!

  assert_equal "replica.example.net", SecretConfig.fetch("mysql/host")
ensure
  ENV.delete("MYSQL_HOST")
  SecretConfig.refresh!
end
~~~

The `refresh!` calls matter. An override of a key that exists in the store is applied when the registry
is loaded, so setting the variable mid-process does nothing until the registry is re-read. See
[Guide, Step 6](api#step-6-override-with-an-environment-variable).

For a key that is **not** in the store, no refresh is needed, because such a key is read from the
environment on every lookup:

~~~ruby
def test_uses_the_feature_flag
  ENV["FEATURES_NEW_CHECKOUT"] = "true"

  assert SecretConfig.fetch("features/new_checkout", type: :boolean)
ensure
  ENV.delete("FEATURES_NEW_CHECKOUT")
end
~~~

## Step 3: Set a value directly

`set` writes to the store. Against the file provider that rewrites `config/application.yml`, which is
not what you want from a test, so this is only appropriate with the in-memory provider from Step 4.

Within a test that already uses one:

~~~ruby
SecretConfig["mysql/host"] = "replica.example.net"

assert_equal "replica.example.net", SecretConfig.fetch("mysql/host")
~~~

## Step 4: Use an in-memory store

For full control, and to keep tests off the filesystem entirely, use a provider that holds everything in
a Hash. Any object answering `each`, `fetch`, `set` and `delete` works, and can be passed to `use`
directly without registering it:

~~~ruby
class InMemoryProvider < SecretConfig::Providers::Provider
  attr_reader :hash

  def initialize(hash = {})
    super()
    @hash = hash.dup
  end

  def each(path)
    hash.each_pair { |key, value| yield(key, value) if key.start_with?(path) }
  end

  def set(key, value)
    hash[key] = value.to_s
  end

  def delete(key)
    hash.delete(key)
  end

  def fetch(key)
    hash[key]
  end
end
~~~

Keys are **absolute**, because that is what providers deal in. The registry strips its root path before
caching:

~~~ruby
provider = InMemoryProvider.new(
  "/test/my_application/mysql/host"     => "127.0.0.1",
  "/test/my_application/mysql/database" => "my_application_test"
)

SecretConfig.use(provider, path: "/test/my_application")

SecretConfig.fetch("mysql/host")
# => "127.0.0.1"
~~~

Now a test can set anything it likes, including keys that do not exist in the real configuration, and
nothing touches a file.

## Step 5: Restore between tests

`SecretConfig.use` replaces the registry outright, so a test that calls it changes global state for
everything after it. Put the suite back the way it was:

~~~ruby
class ActiveSupport::TestCase
  def with_settings(settings)
    provider = InMemoryProvider.new(settings)
    SecretConfig.use(provider, path: "/test/my_application")
    yield
  ensure
    SecretConfig.use(:file, path: "/test")
  end
end
~~~

Used as:

~~~ruby
def test_falls_back_when_the_replica_is_missing
  with_settings("/test/my_application/mysql/host" => "primary.example.net") do
    assert_equal "primary.example.net", MyApp.database_host
  end
end
~~~

Restoring in an `ensure` rather than a teardown keeps the swap scoped to the block, which survives a
failing assertion.

## Testing code that reads settings

Application code should read settings where it uses them rather than caching them, which is the same
advice that makes [`refresh!`](api#step-10-refresh-at-runtime) work. It also makes the code testable:

~~~ruby
# Testable: the block above can change this between calls.
def pool_size
  SecretConfig.fetch("mysql/pool_size", type: :integer)
end

# Not testable: frozen when the file was loaded, before any test ran.
POOL_SIZE = SecretConfig.fetch("mysql/pool_size", type: :integer)
~~~

## Asserting on what is configured

`configuration` returns the whole tree, which is useful for asserting that a deployment has everything
it needs:

~~~ruby
def test_every_required_setting_is_present
  %w[mysql/host mysql/database mysql/username secrets/secret_key_base].each do |key|
    assert SecretConfig.key?(key), "Missing required setting: #{key}"
  end
end
~~~

A test like this belongs in the suite because it catches a missing key at build time rather than at
startup in production. Note that it passes when a key is supplied only by an environment variable, since
that is what [`key?`](api#step-7-ask-whether-a-key-is-set) answers.

## Next steps

* [Guide](api): the interface being tested.
* [Providers](providers): writing a provider, in more detail.
* [Configuration](config): swapping providers outside of tests.
