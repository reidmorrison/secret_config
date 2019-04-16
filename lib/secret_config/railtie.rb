module SecretConfig
  class Railtie < Rails::Railtie
    # Exposes Secret Config's configuration to the Rails application configuration.
    #
    # @example Set up configuration in the Rails app.
    #   module MyApplication
    #     class Application < Rails::Application
    #       config.secret_config.use :file, root: '/development'
    #     end
    #   end
    config.secret_config = SecretConfig
  end
end
