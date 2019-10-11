module SecretConfig
  module Providers
    # Abstract Base provider
    class Provider
      def delete(_key)
        raise NotImplementedError
      end

      def each(_path)
        raise NotImplementedError
      end

      def fetch(_key)
        raise NotImplementedError
      end

      def set(_key, _value)
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
