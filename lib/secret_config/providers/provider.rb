module SecretConfig
  module Providers
    # Abstract Base provider
    class Provider
      def delete(key)
        raise NotImplementedError
      end

      def each(path)
        raise NotImplementedError
      end

      def fetch(key)
        raise NotImplementedError
      end

      def set(key, value)
        raise NotImplementedError
      end

      def to_h(path)
        h = {}
        each(path) { |key, value| h[key] = value }
        h
      end
    end
  end
end
