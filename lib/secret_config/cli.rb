require "forwardable"

module SecretConfig
  # Command line front end for the central store.
  #
  # Talks to a provider directly rather than through the global registry, so that it can operate on
  # any path without SECRET_CONFIG_PATH being set. Option parsing lives in `Options`, and the work
  # each command delegates to lives in `ConfigFile`, `Differ` and `Importer`. What is left here is
  # the dispatch, and the reporting that goes with each command.
  class CLI
    autoload :Colors, "secret_config/cli/colors"
    autoload :ConfigFile, "secret_config/cli/config_file"
    autoload :Differ, "secret_config/cli/differ"
    autoload :Importer, "secret_config/cli/importer"
    autoload :Options, "secret_config/cli/options"

    extend Forwardable

    PROVIDERS = %i[ssm secrets_manager file].freeze

    attr_reader :options

    def_delegators :options,
                   :path, :provider, :file_name, :provider_file,
                   :export, :no_filter, :interpolate,
                   :import, :key_id, :key_alias, :random_size, :prune, :force,
                   :fetch_key, :delete_key, :set_key, :set_value, :delete_tree,
                   :diff,
                   :console,
                   :show_version,
                   :parser

    def self.run!(argv)
      new(argv).run!
    end

    def initialize(argv)
      @options = Options.new(argv)
    end

    def run!
      if show_version
        puts "Secret Config v#{VERSION}"
      elsif console
        run_console
      elsif export
        run_export
      elsif import
        run_import
      elsif diff
        run_diff
      elsif set_key
        run_set(set_key, set_value)
      elsif fetch_key
        run_fetch(fetch_key)
      elsif delete_key
        run_delete(delete_key)
      elsif delete_tree
        run_delete_tree(delete_tree)
      else
        puts parser
      end
    end

    private

    def provider_instance
      @provider_instance ||=
        case provider
        when :ssm
          Providers::Ssm.new(**kms_args)
        when :secrets_manager
          Providers::SecretsManager.new(**kms_args)
        when :file
          Providers::File.new(file_name: provider_file)
        else
          raise ArgumentError, "Invalid provider: #{provider}. Valid providers: #{PROVIDERS.join(' | ')}"
        end
    end

    # Returns [Hash] the KMS key to build an AWS provider with, empty when neither option was supplied
    # so that the provider falls back to its own default rather than being handed an explicit nil.
    def kms_args
      return {key_alias: key_alias} if key_alias
      return {key_id: key_id} if key_id

      {}
    end

    def importer
      @importer ||= Importer.new(provider: provider_instance, random_size: random_size)
    end

    def run_export
      raise(ArgumentError, "--path option is not valid for --export") if path

      target = file_name || $stdout
      puts("Exporting #{provider}:#{export} to #{target}") if target.is_a?(String)

      ConfigFile.new(target).write(fetch_config(export, filtered: !no_filter))
    end

    def run_import
      path ? import_from_path(import, path) : import_from_file(import, file_name || $stdin)
    end

    def import_from_file(target_path, source_file)
      puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
      puts "+++ #{source_file}#{Colors::CLEAR}"

      import_config(ConfigFile.new(source_file).read, target_path)
    end

    def import_from_path(target_path, source_path)
      puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
      puts "+++ #{provider}:#{source_path}#{Colors::CLEAR}"

      import_config(fetch_config(source_path, filtered: false), target_path)

      puts("Imported #{target_path} from #{source_path} on provider: #{provider}")
    end

    def import_config(config, target_path)
      importer.import(config, target_path, current_values(target_path), prune: prune, force: force)
    end

    def run_diff
      path ? diff_against_path(diff, path) : diff_against_file(diff, file_name || $stdin)
    end

    def diff_against_file(target_path, source_file)
      source = Utils.flatten(ConfigFile.new(source_file).read, target_path)
      target = Utils.flatten(fetch_config(target_path, filtered: false), target_path)

      if source_file.is_a?(String)
        puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
        puts "+++ #{source_file}#{Colors::CLEAR}"
      end

      Differ.display(target, source)
    end

    def diff_against_path(target_path, source_path)
      source = Utils.flatten(fetch_config(source_path, filtered: false))
      target = Utils.flatten(fetch_config(target_path, filtered: false))

      puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
      puts "+++ #{provider}:#{source_path}#{Colors::CLEAR}"

      Differ.display(target, source)
    end

    # IRB is required here rather than at the top of the file because it stops being a default gem in
    # Ruby 4.0. An unconditional require warns under bundler now, and fails there once it has to be
    # declared, which would break every other command for the sake of this one.
    def run_console
      begin
        require "irb"
      rescue LoadError => e
        raise(LoadError, "Add gem 'irb' to use `secret-config --console`: #{e.message}")
      end

      IRB.start
    end

    def run_delete(key)
      puts "#{Colors::TITLE}--- #{provider}:#{path}"
      puts "#{Colors::REMOVE}- #{key}#{Colors::CLEAR}"
      provider_instance.delete(key)
    end

    def run_delete_tree(path)
      source_config = fetch_config(path)
      puts "#{Colors::TITLE}--- #{provider}:#{path}#{Colors::CLEAR}"

      source = Utils.flatten(source_config, path)
      source.each_key do |key|
        puts "#{Colors::REMOVE}- #{key}#{Colors::CLEAR}"
        provider_instance.delete(key)
      end
    end

    def run_fetch(key)
      value = provider_instance.fetch(key)
      puts value if value
    end

    def run_set(key, value)
      provider_instance.set(key, value)
    end

    def fetch_config(path, filtered: true)
      registry = Registry.new(path: path, provider: provider_instance, interpolate: interpolate)
      config   = filtered ? registry.configuration : registry.configuration(filters: nil)
      Utils.sort_by_key!(config)
    end

    # Only used by `import_config`, to decide which keys are new and which changed.
    # A target that does not exist yet has no current values. SSM already behaves that way, since a path
    # with no parameters under it simply yields nothing. The file provider instead raises for both a
    # missing file and a missing path, so treat that as the empty store it is: importing is what creates it.
    def current_values(path)
      Utils.flatten(fetch_config(path, filtered: false), path)
    rescue ConfigurationError
      {}
    end
  end
end
