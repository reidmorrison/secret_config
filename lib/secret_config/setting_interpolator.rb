require "date"
require "socket"
require "securerandom"
# * SecretConfig Interpolations
#
# Expanding values inline for date, time, hostname, pid and random values.
#   ${date}           # Current date in the format of "%Y%m%d" (CCYYMMDD)
#   ${date:format}    # Current date in the supplied format. See strftime
#   ${time}           # Current date and time down to ms in the format of "%Y%m%d%Y%H%M%S%L" (CCYYMMDDHHMMSSmmm)
#   ${time:format}    # Current date and time in the supplied format. See strftime
#   ${env:name}       # Extract value from the named environment value.
#   ${hostname}       # Full name of this host.
#   ${hostname:short} # Short name of this host. Everything up to the first period.
#   ${pid}            # Process Id for this process.
#   ${random}         # URL safe Random 32 byte value.
#   ${random:size}    # URL safe Random value of `size` bytes.
module SecretConfig
  class SettingInterpolator < StringInterpolator
    def date(format = "%Y%m%d")
      Date.today.strftime(format)
    end

    def time(format = "%Y%m%d%H%M%S%L")
      Time.now.strftime(format)
    end

    def env(name, default = :no_default_supplied)
      return ENV[name] if ENV.key?(name)

      return default unless default == :no_default_supplied

      raise(MissingEnvironmentVariable, "Missing mandatory environment variable: #{name}")
    end

    def hostname(format = nil)
      name = Socket.gethostname
      name = name.split(".")[0] if format == "short"
      name
    end

    def pid
      $$
    end

    def random(size = 32)
      SecureRandom.urlsafe_base64(size)
    end
  end
end
