# Parse strings containing ${key:value1,value2,value3}
# Where `key` is one of the interpolations declared by a class inheriting from this class.
#
# Only declared interpolations are dispatched. A subclass makes a method reachable as `${name}` by
# naming it in an `interpolation` declaration:
#
#   class MyInterpolator < SecretConfig::StringInterpolator
#     interpolation :colour
#
#     def colour(name = "red")
#       name
#     end
#   end
#
# Anything else raises `InvalidInterpolation`, including the methods every object inherits. Dispatch
# used to be guarded by `respond_to?`, which let a value in the central store call `Object#send` and
# from there run arbitrary code when the configuration was loaded.
#
# Notes:
# * To prevent interpolation use $${...}
# * $$ is not touched, only ${...} is identified.
module SecretConfig
  class StringInterpolator
    PATTERN = /\${1,2}\{([^}]+)\}/

    class << self
      # Declares the interpolations this class supplies, in addition to those of its superclass.
      def interpolation(*names)
        declared_interpolations.concat(names.map(&:to_sym))
      end

      # Returns [Array<Symbol>] every interpolation this class dispatches, its own and inherited.
      def interpolations
        return declared_interpolations unless superclass.respond_to?(:interpolations)

        superclass.interpolations + declared_interpolations
      end

      private

      # Held per class rather than merged into one list, so that a subclass declared after this is
      # first read still sees everything its superclass declares.
      def declared_interpolations
        @declared_interpolations ||= []
      end
    end

    # `pattern` is ignored. It has never been used: `parse` has always matched with `PATTERN`.
    # Removing the argument would break any caller still supplying it, so it goes in the next major
    # release rather than here.
    def initialize(pattern = nil)
      @pattern = pattern || PATTERN
    end

    def parse(string)
      string.gsub(PATTERN) do |match|
        match.start_with?("$$") ? match[1..] : interpolate(Regexp.last_match(1), match)
      end
    end

    private

    attr_reader :pattern

    # Returns [String] the value the supplied expression interpolates to.
    # `match` is the token it came from, and is only used to make the errors below point at it.
    def interpolate(expression, match)
      key, args_str = expression.split(":")
      key           = key.to_s.strip.to_sym

      raise(InvalidInterpolation, "Invalid key: #{key} in string: #{match}") unless self.class.interpolations.include?(key)

      arguments = args_str&.split(",")&.map { |value| value.strip == "" ? nil : value.strip } || []

      begin
        public_send(key, *arguments)
      rescue ArgumentError => e
        raise(InvalidInterpolation, "Invalid arguments for key: #{key} in string: #{match}. #{e.message}")
      end
    end
  end
end
