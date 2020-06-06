module SecretConfig
  class Parser
    attr_reader :tree, :path, :registry, :interpolator

    def initialize(path, registry, interpolate: true)
      @path         = path
      @registry     = registry
      @fetch_list   = {}
      @import_list  = {}
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

    # def apply_fetches
    #   tree[key] = relative_key?(fetch_key) ? registry[fetch_key] : registry.provider.fetch(fetch_key)
    # end

    # Import from the current registry as well as new fetches.
    #
    # Notes:
    # - A lot of absolute key lookups can be expensive since each one is a separate call.
    # - Imports cannot reference other imports at this time.
    def apply_imports
      tree.keys.each do |key|
        next unless (key =~ /\/__import__\Z/) || (key == "__import__")

        import_key = tree.delete(key)
        key, _     = ::File.split(key)
        key        = nil if key == "."

        # binding.irb

        # With a relative key, look for the values in the current registry.
        # With an absolute key call the provider and fetch the value directly.

        if relative_key?(import_key)
          tree.keys.each do |current_key|
            match = current_key.match(/\A#{import_key}\/(.*)/)
            next unless match

            imported_key       = key.nil? ? match[1] : ::File.join(key, match[1])
            tree[imported_key] = tree[current_key] unless tree.key?(imported_key)
          end
        else
          relative_paths = registry.send(:fetch_path, import_key)
          relative_paths.each_pair do |relative_key, value|
            imported_key       = key.nil? ? relative_key : ::File.join(key, relative_key)
            tree[imported_key] = value unless tree.key?(imported_key)
          end
        end
      end
    end

    # Returns [true|false] whether the supplied key is considered a relative key.
    def relative_key?(key)
      !key.start_with?("/")
    end

  end
end
