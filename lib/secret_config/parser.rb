module SecretConfig
  class Parser
    attr_reader :tree, :path, :registry, :interpolator

    def initialize(path, registry)
      @fetch_list   = {}
      @import_list  = {}
      @tree         = {}
      @path         = path
      @interpolator = SettingInterpolator.new
    end

    # Returns a flat path of keys and values from the provider without looking in the local path.
    # Keys are returned with path names relative to the supplied path.
    def parse(key, value)
      relative_key       = relative_key?(key) ? key : key.sub("#{path}/", "")
      tree[relative_key] = value.is_a?(String) && value.include?("%{") ? interpolator.parse(value) : value
    end

    # Returns a flat Hash of the rendered paths.
    def render
      # apply_fetches
      # apply_imports
      tree
    end

    private

    # def apply_fetches
    #   interpolator.fetch_list.each_pair do |key, fetch_key|
    #     tree[key] = relative_key?(fetch_key) ? registry[fetch_key] : registry.provider.fetch(fetch_key)
    #   end
    # end

    # Imports cannot reference other imports at this time.
    # def apply_imports
    #   interpolator.import_list.each_pair do |key, import_key|
    #     relative_paths =
    #       if relative_key?(import_key)
    #         registry.configuration(path: import_key, relative: true, filters: nil)
    #       else
    #         registry.fetch_path(import_key)
    #       end
    #     relative_paths.each_pair { |relative_key, value| tree[::File.join(key, relative_key)] = value }
    #   end
    # end

    # Returns [true|false] whether the supplied key is considered a relative key.
    def relative_key?(key)
      !key.start_with?("/")
    end

  end
end
