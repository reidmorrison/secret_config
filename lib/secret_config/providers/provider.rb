module SecretConfig
  module Providers
    # Abstract Base provider
    class Provider
      def set(key, value)
        raise NotImplementedError
      end

      def delete(key)
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
