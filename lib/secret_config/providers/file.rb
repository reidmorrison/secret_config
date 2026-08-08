require "yaml"
require "erb"
require "fileutils"

module SecretConfig
  module Providers
    # Read configuration from a local file
    class File < Provider
      DEFAULT_FILE_NAME = "config/application.yml".freeze

      attr_reader :file_name

      # The file does not have to exist yet. Reads raise when it is missing, writes create it, so that
      # an import can bootstrap a new store. `SecretConfig.use(:file)` still fails at the same point as
      # before, since `Registry#refresh!` reads immediately.
      def initialize(file_name: nil)
        super()
        @file_name = file_name || ENV["SECRET_CONFIG_FILE_NAME"] || DEFAULT_FILE_NAME
      end

      # Yields the key with its absolute path and corresponding string value
      def each(path, &)
        settings = fetch_path(path)

        raise(ConfigurationError, "Path #{path} not found in file: #{file_name}") unless settings

        Utils.flatten_each(settings, path, &)
        nil
      end

      # Returns the value or `nil` if not found.
      # A key that is both a value and a node holds its own value under `NODE_KEY`, which is what `each`
      # yields for it, so return that rather than `nil`.
      def fetch(key)
        values = fetch_path(key)
        values.is_a?(Hash) ? values[NODE_KEY] : values
      end

      # Writes `value` at `key`, creating any intermediate nodes, and rewrites the entire file.
      # A key that is already a node keeps its children and stores its own value under `NODE_KEY`,
      # which is how the flat provider model is represented in a nested file.
      def set(key, value)
        config = writable_config
        paths  = split_key(key)
        name   = paths.pop
        node   = paths.reduce(config) { |target, path| descend(target, path) }

        existing = node[name]
        if existing.is_a?(Hash)
          existing[NODE_KEY] = value
        else
          node[name] = value
        end

        write_config(config)
        value
      end

      # Removes `key`, and any nodes it leaves empty. Deleting a key that is also a node removes only
      # its own value, leaving the children in place, since those are separate keys in the flat model.
      def delete(key)
        config = writable_config
        paths  = split_key(key)
        name   = paths.pop
        nodes  = [config]
        paths.each do |path|
          node = nodes.last[path]
          return nil unless node.is_a?(Hash)

          nodes << node
        end

        existing = nodes.last[name]
        if existing.is_a?(Hash)
          existing.delete(NODE_KEY)
        else
          return nil unless nodes.last.key?(name)

          nodes.last.delete(name)
        end

        prune_empty(nodes, paths)
        write_config(config)
        nil
      end

      private

      def fetch_path(path)
        raise(ConfigurationError, "Cannot find config file: #{file_name}") unless ::File.exist?(file_name)

        config = load_yaml(ERB.new(::File.read(file_name)).result)

        config.dig(*split_key(path))
      end

      def split_key(key)
        key.sub(%r{\A/*}, "").sub(%r{/*\Z}, "").split("/")
      end

      # Returns the node at `path` under `target`, creating it when absent. A node that currently holds
      # a value keeps it under `NODE_KEY` so that the value and its children can coexist.
      def descend(target, path)
        child = target[path]
        return child if child.is_a?(Hash)
        return target[path] = {} unless target.key?(path)

        target[path] = {NODE_KEY => child}
      end

      # Walks back up the path removing nodes that a delete left empty.
      def prune_empty(nodes, paths)
        paths.reverse_each.with_index do |path, index|
          node = nodes[-1 - index]
          break unless node.is_a?(Hash) && node.empty?

          nodes[-2 - index].delete(path)
        end
      end

      # The file is rewritten from its parsed contents, so anything that does not survive a YAML round
      # trip is lost. Comments and formatting go either way; ERB would be baked in as its evaluated
      # result, silently turning a template into a literal, so refuse to write rather than destroy it.
      def writable_config
        return {} unless ::File.exist?(file_name)

        source = ::File.read(file_name)
        if source.match?(/<%/)
          raise(ConfigurationError,
                "Cannot write to config file containing ERB: #{file_name}. " \
                "Writing rewrites the file from its parsed contents, which would replace the ERB with its " \
                "evaluated result. Edit the file directly instead.")
        end

        load_yaml(source) || {}
      end

      def write_config(config)
        FileUtils.mkdir_p(::File.dirname(file_name))
        ::File.write(file_name, config.to_yaml)
      end

      def load_yaml(src)
        return YAML.safe_load(src, permitted_classes: [Symbol], aliases: true) if Psych::VERSION > "4.0"

        YAML.load(src)
      end
    end
  end
end
