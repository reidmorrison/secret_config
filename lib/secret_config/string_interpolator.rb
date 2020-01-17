# Parse strings containing %{key:value1,value2,value3}
# Where `key` is a method implemented by a class inheriting from this class
#
# The following `key`s are reserved:
# * parse
# * initialize
#
# Notes:
# * To prevent interpolation use %%{...}
# * %% is not touched, only %{...} is identified.
module SecretConfig
  class StringInterpolator
    def initialize(pattern = nil)
      @pattern = pattern || /%{1,2}\{([^}]+)\}/
    end

    def parse(string)
      string.gsub(/%{1,2}\{([^}]+)\}/) do |match|
        if match.start_with?('%%')
          match[1..-1]
        else
          expr          = $1 || $2 || match.tr("%{}", "")
          key, args_str = expr.split(':')
          key           = key.to_sym
          arguments     = args_str&.split(',')&.map { |v| v == '' ? nil : v } || []
          raise(InvalidInterpolation, "Invalid key: #{key} in string: #{match}") unless respond_to?(key)
          public_send(key, *arguments)
        end
      end
    end
  end
end
