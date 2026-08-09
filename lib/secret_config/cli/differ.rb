module SecretConfig
  class CLI
    # Displays the difference between two flat key/value hashes, in the style of a unified diff.
    # `target` supplies the removals, `source` the additions.
    #
    # `filters` masks the values of keys that hold secrets, defaulting to the same set `--export`
    # uses. Masking is applied when the value is printed, never before the two sides are compared,
    # so a password that changed is still reported as changed; only its value is withheld. Pass
    # `filters: nil`, which is what `--no-filter` does, to print everything in the clear.
    module Differ
      def self.display(target, source, filters: SecretConfig.filters)
        (source.keys + target.keys).sort.uniq.each { |key| display_key(key, target, source, filters) }
      end

      def self.display_key(key, target, source, filters)
        if !target.key?(key)
          display_added(key, source[key], filters) if source.key?(key)
        elsif !source.key?(key)
          display_removed(key, target[key], filters)
        else
          display_changed(key, target[key], source[key], filters)
        end
      end
      private_class_method :display_key

      # Filtered values are ignored: an export filters secrets by default, so a `[FILTERED]` source
      # value means the secret was never in the file, not that it changed.
      def self.display_changed(key, target_value, source_value, filters)
        value = source_value.to_s
        return if (value == target_value.to_s) || (value == FILTERED)

        puts "#{Colors::KEY}#{key}:"
        puts "#{Colors::REMOVE}#{prefix_lines('- ', mask(key, target_value, filters))}"
        puts "#{Colors::ADD}#{prefix_lines('+ ', mask(key, source_value, filters))}#{Colors::CLEAR}\n\n"
      end
      private_class_method :display_changed

      def self.display_removed(key, value, filters)
        puts "#{Colors::KEY}#{key}:"
        puts "#{Colors::REMOVE}#{prefix_lines('- ', mask(key, value, filters))}\n\n"
      end
      private_class_method :display_removed

      def self.display_added(key, value, filters)
        puts "#{Colors::KEY}#{key}:"
        puts "#{Colors::ADD}#{prefix_lines('+ ', mask(key, value, filters))}#{Colors::CLEAR}\n\n"
      end
      private_class_method :display_added

      def self.mask(key, value, filters)
        Utils.filtered?(key, filters) ? FILTERED : value
      end
      private_class_method :mask

      def self.prefix_lines(prefix, value)
        value.to_s.lines.collect { |line| "#{prefix}#{line}" }.join
      end
      private_class_method :prefix_lines
    end
  end
end
