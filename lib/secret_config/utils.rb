module SecretConfig
  module Utils
    # Takes a hierarchical structure and flattens it to a single level
    # If path is supplied it is prepended to every key returned
    def self.flatten_each(hash, path = nil, &block)
      hash.each_pair do |key, value|
        name = path.nil? ? key : "#{path}/#{key}"
        value.is_a?(Hash) ? flatten_each(value, name, &block) : yield(name, value)
      end
    end

    def self.constantize_symbol(symbol, namespace = 'SecretConfig::Providers')
      klass = "#{namespace}::#{camelize(symbol.to_s)}"
      begin
        Object.const_get(klass)
      rescue NameError
        raise(ArgumentError, "Could not convert symbol: #{symbol.inspect} to a class in: #{namespace}. Looking for: #{klass}")
      end
    end

    # Borrow from Rails, when not running Rails
    def self.camelize(term)
      string = term.to_s
      string = string.sub(/^[a-z\d]*/, &:capitalize)
      string.gsub!(/(?:_|(\/))([a-z\d]*)/i) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).capitalize}" }
      string.gsub!('/'.freeze, '::'.freeze)
      string
    end
  end
end
