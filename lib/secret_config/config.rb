module SecretConfig
  class Config
    extend Forwardable
    def_delegator :registry, :configuration
    def_delegator :registry, :refresh!

    def initialize(path, registry)
      @path     = path
      @registry = registry
    end

    def fetch(sub_path, **options)
      registry.fetch(join_path(sub_path), **options)
    end

    def [](sub_path)
      registry[join_path(sub_path)]
    end

    def []=(sub_path, value)
      registry[join_path(sub_path)] = value
    end

    def key?(sub_path)
      registry.key?(join_path(sub_path))
    end

    def set(sub_path, value)
      registry.set(join_path(sub_path), value)
    end

    def delete(sub_path)
      registry.delete(join_path(sub_path))
    end

    private

    attr_reader :path, :registry

    def join_path(sub_path)
      File.join(path, sub_path)
    end
  end
end
