module SecretConfig
  class Parser
    attr_reader :tree, :path, :registry, :interpolator

    def initialize(path, registry, interpolate: true)
      @path         = path
      @registry     = registry
      @tree         = {}
      @interpolator = interpolate ? SettingInterpolator.new : nil
    end

    # Returns a flat path of keys and values from the provider without looking in the local path.
    # Keys are returned with path names relative to the supplied path.
    def parse(key, value)
      relative_key       = relative_key?(key) ? key : key.sub("#{path}/", "")
      value              = interpolator.parse(value) if interpolator && value.is_a?(String) && value.include?("${")
      tree[relative_key] = value
    end

    # Returns a flat Hash of the rendered paths.
    def render
      apply_imports if interpolator
      tree
    end

    private

    # Import from the current registry as well as new fetches.
    #
    # Notes:
    # - A lot of absolute key lookups can be expensive since each one is a separate call.
    def apply_imports
      # Collect the keys up front, since applying an import adds to and deletes from the tree.
      import_keys = tree.keys.select { |key| import_key?(key) }
      import_keys.each { |key| apply_import(key, []) }
    end

    # Replaces the supplied import key with the settings under the path it refers to.
    #
    # `chain` holds the import keys currently being resolved, so that a circular reference raises
    # instead of recursing forever.
    def apply_import(key, chain)
      # Already resolved, as a dependency of an import that was applied before this one.
      return unless tree.key?(key)

      if chain.include?(key)
        raise(ConfigurationError,
              "Circular #{IMPORT_KEY} in #{path}: #{(chain + [key]).join(' -> ')}")
      end

      source_path = tree[key]

      # With a relative path, look for the values in the current registry.
      # With an absolute path call the provider and fetch the values directly.
      values =
        if relative_key?(source_path)
          apply_nested_imports(source_path, chain + [key])
          relative_values(source_path)
        else
          registry.send(:fetch_path, source_path)
        end

      tree.delete(key)
      target_path = ::File.split(key).first
      target_path = nil if target_path == "."

      values.each_pair do |relative_key, value|
        imported_key       = target_path.nil? ? relative_key : ::File.join(target_path, relative_key)
        tree[imported_key] = value unless tree.key?(imported_key)
      end
    end

    # Resolves any imports inside the subtree that is about to be imported, so that the values they
    # bring in are imported too, regardless of the order in which the keys were read.
    def apply_nested_imports(source_path, chain)
      prefix      = "#{source_path}/"
      nested_keys = tree.keys.select { |key| import_key?(key) && key.start_with?(prefix) }
      nested_keys.each { |key| apply_import(key, chain) }
    end

    # Returns [Hash] the values under the supplied path, with keys relative to that path.
    def relative_values(source_path)
      prefix = "#{source_path}/"
      values = {}
      tree.each_pair do |key, value|
        values[key.delete_prefix(prefix)] = value if key.start_with?(prefix)
      end
      values
    end

    # Returns [true|false] whether the supplied key imports another path into its parent node.
    def import_key?(key)
      (key == IMPORT_KEY) || key.end_with?("/#{IMPORT_KEY}")
    end

    # Returns [true|false] whether the supplied key is considered a relative key.
    def relative_key?(key)
      !key.start_with?("/")
    end
  end
end
