module SecretConfig
  module Utils
    # Takes a hierarchical structure and flattens it to a single level.
    # If path is supplied it is prepended to every key returned.
    def self.flatten_each(hash, path = nil, &block)
      hash.each_pair do |key, value|
        if key == NODE_KEY
          yield(path, value)
        else
          name = path.nil? ? key : "#{path}/#{key}"
          value.is_a?(Hash) ? flatten_each(value, name, &block) : yield(name, value)
        end
      end
    end

    # Takes a hierarchical structure and flattens it to a single level hash.
    # If path is supplied it is prepended to every key returned.
    def self.flatten(hash, path = nil)
      h = {}
      flatten_each(hash, path) { |key, value| h[key] = value }
      h
    end

    # Takes a flat hash and expands the keys on each `/` into a deep hierarchy.
    def self.hierarchical(flat_hash)
      h = {}
      flat_hash.each_pair { |path, value| decompose(path, value, h) }
      h
    end

    def self.decompose(key, value, h = {})
      full_path, name = File.split(key)
      if full_path == "."
        h[key] = value
        return h
      end
      last       = full_path.split("/").reduce(h) do |target, path|
        if path == ""
          target
        elsif target.key?(path)
          val = target[path]
          val = target[path] = {NODE_KEY => val} unless val.is_a?(Hash)
          val
        else
          target[path] = {}
        end
      end
      last[name] = value
      h
    end

    def self.constantize_symbol(symbol, namespace = "SecretConfig::Providers")
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
      string.gsub!(%r{(?:_|(/))([a-z\d]*)}i) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).capitalize}" }
      string.gsub!("/".freeze, "::".freeze)
      string
    end
  end
end
