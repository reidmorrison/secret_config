module SecretConfig
  class CLI
    # Displays the difference between two flat key/value hashes, in the style of a unified diff.
    # `target` supplies the removals, `source` the additions.
    module Differ
      def self.display(target, source)
        (source.keys + target.keys).sort.uniq.each { |key| display_key(key, target, source) }
      end

      def self.display_key(key, target, source)
        if !target.key?(key)
          display_added(key, source[key]) if source.key?(key)
        elsif !source.key?(key)
          display_removed(key, target[key])
        else
          display_changed(key, target[key], source[key])
        end
      end
      private_class_method :display_key

      # Filtered values are ignored: an export filters secrets by default, so a `[FILTERED]` source
      # value means the secret was never in the file, not that it changed.
      def self.display_changed(key, target_value, source_value)
        value = source_value.to_s
        return if (value == target_value.to_s) || (value == FILTERED)

        puts "#{Colors::KEY}#{key}:"
        puts "#{Colors::REMOVE}#{prefix_lines('- ', target_value)}"
        puts "#{Colors::ADD}#{prefix_lines('+ ', source_value)}#{Colors::CLEAR}\n\n"
      end
      private_class_method :display_changed

      def self.display_removed(key, value)
        puts "#{Colors::KEY}#{key}:"
        puts "#{Colors::REMOVE}#{prefix_lines('- ', value)}\n\n"
      end
      private_class_method :display_removed

      def self.display_added(key, value)
        puts "#{Colors::KEY}#{key}:"
        puts "#{Colors::ADD}#{prefix_lines('+ ', value)}#{Colors::CLEAR}\n\n"
      end
      private_class_method :display_added

      def self.prefix_lines(prefix, value)
        value.to_s.lines.collect { |line| "#{prefix}#{line}" }.join
      end
      private_class_method :prefix_lines
    end
  end
end
