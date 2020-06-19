module SecretConfig
  class Config
    extend Forwardable
    def_delegator :registry, :configuration
    def_delegator :registry, :refresh!

    def initialize(path, registry)
      raise(ArgumentError, "path cannot be nil") if path.nil?

      @path     = path
      @registry = registry
    end

    def fetch(sub_path, **options)
      raise(ArgumentError, "sub_path cannot be nil") if sub_path.nil?

      registry.fetch(join_path(sub_path), **options)
    end

    def [](sub_path)
      raise(ArgumentError, "sub_path cannot be nil") if sub_path.nil?

      registry[join_path(sub_path)]
    end

    def []=(sub_path, value)
      raise(ArgumentError, "sub_path cannot be nil") if sub_path.nil?

      registry[join_path(sub_path)] = value
    end

    def key?(sub_path)
      raise(ArgumentError, "sub_path cannot be nil") if sub_path.nil?

      registry.key?(join_path(sub_path))
    end

    def set(sub_path, value)
      raise(ArgumentError, "sub_path cannot be nil") if sub_path.nil?

      registry.set(join_path(sub_path), value)
    end

    def delete(sub_path)
      raise(ArgumentError, "sub_path cannot be nil") if sub_path.nil?

      registry.delete(join_path(sub_path))
    end

    private

    attr_reader :path, :registry

    def join_path(sub_path)
      File.join(path, sub_path)
    end
  end
end
