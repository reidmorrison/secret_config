module SecretConfig
  module Utils
    # Mode for a file this gem creates that can hold configuration values in the clear.
    PRIVATE_FILE_MODE = 0o600

    # Writes `data` to `file_name`, creating it readable only by its owner.
    #
    # Every caller writes settings in the clear, and `::File.write` would create the file with
    # whatever the umask allows, which is world readable by default on most systems.
    #
    # A file that already exists keeps the mode it has: it may have been widened deliberately, and
    # a write is no place to change that silently. Warn instead, once per file per process, since
    # the file provider rewrites the whole file on every `set`.
    def self.write_private_file(file_name, data)
      warn_when_readable(file_name) if ::File.exist?(file_name)

      ::File.open(file_name, ::File::WRONLY | ::File::CREAT | ::File::TRUNC, PRIVATE_FILE_MODE) do |io|
        io.write(data)
      end
      data
    end

    # File modes are not meaningful on every platform, so report rather than enforce.
    def self.warn_when_readable(file_name)
      mode = ::File.stat(file_name).mode & 0o777
      return if mode.nobits?(0o077)

      SecretConfig.warn_once(
        "#{file_name} is readable by users other than its owner (mode #{format('%04o', mode)}) and can " \
        "hold settings in the clear. Run: chmod 600 #{file_name}"
      )
    end
    private_class_method :warn_when_readable

    # Takes a hierarchical structure and flattens it to a single level.
    # If path is supplied it is prepended to every key returned.
    def self.flatten_each(hash, path = nil, &block)
      hash.each_pair do |key, value|
        if key == NODE_KEY
          yield(path, value)
        else
          name = path.nil? ? key : File.join(path, key)
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

    def self.decompose(key, value, hash = {})
      full_path, name = File.split(key)
      if full_path == "."
        hash[key] = value
        return hash
      end
      last = full_path.split("/").reduce(hash) do |target, path|
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
      hash
    end

    # Sorts a nested hash by key, in place, at every level.
    # Keeps exports, imports and diffs in a stable order regardless of the order the provider yields.
    def self.sort_by_key!(hash)
      hash.keys.sort.each do |key|
        value = hash[key] = hash.delete(key)
        sort_by_key!(value) if value.is_a?(Hash)
      end
      hash
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
