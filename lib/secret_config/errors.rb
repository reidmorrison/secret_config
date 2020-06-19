module SecretConfig
  class Error < StandardError
  end

  class MissingMandatoryKey < Error
  end

  class MissingEnvironmentVariable < Error
  end

  class UndefinedRootError < Error
  end

  class ConfigurationError < Error
  end

  class InvalidInterpolation < Error
  end
end
