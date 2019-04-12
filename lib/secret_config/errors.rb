module SecretConfig
  class Error < StandardError
  end

  class MissingMandatoryKey < Error
  end

  class UndefinedRootError < Error
  end

  class ConfigurationError < Error
  end
end
