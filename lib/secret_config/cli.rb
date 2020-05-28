require "optparse"
require "fileutils"
require "erb"
require "yaml"
require "json"
require "securerandom"
require "irb"

module SecretConfig
  class CLI
    module Colors
      CLEAR   = "\e[0m".freeze
      BOLD    = "\e[1m".freeze
      BLACK   = "\e[30m".freeze
      RED     = "\e[31m".freeze
      GREEN   = "\e[32m".freeze
      YELLOW  = "\e[33m".freeze
      BLUE    = "\e[34m".freeze
      MAGENTA = "\e[35m".freeze
      CYAN    = "\e[36m".freeze
      WHITE   = "\e[37m".freeze

      TITLE  = "\e[1m".freeze
      KEY    = "\e[36m".freeze
      REMOVE = "\e[31m".freeze
      ADD    = "\e[32m".freeze
    end

    attr_reader :path, :provider, :file_name,
                :export, :no_filter, :interpolate,
                :import, :key_id, :key_alias, :random_size, :prune, :force,
                :diff_path, :import_path,
                :fetch_key, :delete_key, :set_key, :set_value, :delete_tree,
                :copy_path, :diff,
                :console,
                :show_version

    PROVIDERS = %i[ssm].freeze

    def self.run!(argv)
      new(argv).run!
    end

    def initialize(argv)
      @export       = false
      @import       = false
      @path         = nil
      @key_id       = nil
      @key_alias    = nil
      @provider     = :ssm
      @random_size  = 32
      @no_filter    = false
      @prune        = false
      @replace      = false
      @copy_path    = nil
      @show_version = false
      @console      = false
      @diff         = false
      @set_key      = nil
      @set_value    = nil
      @fetch_key    = nil
      @delete_key   = nil
      @delete_tree  = nil
      @diff_path    = nil
      @import_path  = nil
      @force        = false
      @interpolate  = false

      if argv.empty?
        puts parser
        exit(-10)
      end
      parser.parse!(argv)
    end

    def run!
      if show_version
        puts "Secret Config v#{VERSION}"
      elsif console
        run_console
      elsif export
        raise(ArgumentError, "--path option is not valid for --export") if path

        run_export(export, file_name || STDOUT, filtered: !no_filter)
      elsif import
        if path
          run_import_path(import, path, prune, force)
        else
          run_import(import, file_name || STDIN, prune, force)
        end
      elsif diff
        if path
          run_diff_path(diff, path)
        else
          run_diff(diff, file_name || STDIN)
        end
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

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = <<~BANNER
          Secret Config v#{VERSION}

            For more information, see: https://rocketjob.github.io/secret_config/

          secret-config [options]
        BANNER

        opts.on "-e", "--export SOURCE_PATH", "Export configuration. Use --file to specify the file name, otherwise stdout is used." do |path|
          @export = path
        end

        opts.on "-i", "--import TARGET_PATH", "Import configuration. Use --file to specify the file name, --path for the SOURCE_PATH, otherwise stdin is used." do |path|
          @import = path
        end

        opts.on "-f", "--file FILE_NAME", "Import/Export/Diff to/from this file." do |file_name|
          @file_name = file_name
        end

        opts.on "-p", "--path PATH", "Import/Export/Diff to/from this path." do |path|
          @path = path
        end

        opts.on "--diff TARGET_PATH", "Compare configuration to this path. Use --file to specify the source file name, --path for the SOURCE_PATH, otherwise stdin is used." do |file_name|
          @diff = file_name
        end

        opts.on "-s", "--set KEY=VALUE", "Set one key to value. Example: --set mysql/database=localhost" do |param|
          @set_key, @set_value = param.split("=")
          unless @set_key && @set_value
            raise(ArgumentError, "Supply key and value separated by '='. Example: --set mysql/database=localhost")
          end
        end

        opts.on "-f", "--fetch KEY", "Fetch the value for one setting. Example: --fetch mysql/database." do |key|
          @fetch_key = key
        end

        opts.on "-d", "--delete KEY", "Delete one specific key." do |key|
          @delete_key = key
        end

        opts.on "-r", "--delete-tree PATH", "Recursively delete all keys under the specified path." do |path|
          @delete_tree = path
        end

        opts.on "-c", "--console", "Start interactive console." do
          @console = true
        end

        opts.on "--provider PROVIDER", "Provider to use. [ssm | file]. Default: ssm" do |provider|
          @provider = provider.to_sym
        end

        opts.on "--no-filter", "For --export only. Do not filter passwords and keys." do
          @no_filter = true
        end

        opts.on "--interpolate", "For --export only. Evaluate string interpolation and __import__." do
          @interpolate = true
        end

        opts.on "--prune", "For --import only. During import delete all existing keys for which there is no key in the import file. Only works with --import." do
          @prune = true
        end

        opts.on "--force", "For --import only. Overwrite all values, not just the changed ones. Useful for changing the KMS key." do
          @force = true
        end

        opts.on "--key_id KEY_ID", "For --import only. Encrypt config settings with this AWS KMS key id. Default: AWS Default key." do |key_id|
          @key_id = key_id
        end

        opts.on "--key_alias KEY_ALIAS", "For --import only. Encrypt config settings with this AWS KMS alias." do |key_alias|
          @key_alias = key_alias
        end

        opts.on "--random_size INTEGER", Integer, "For --import only. Size to use when generating random values when $(random) is encountered in the source. Default: 32" do |random_size|
          @random_size = random_size
        end

        opts.on "-v", "--version", "Display Secret Config version." do
          @show_version = true
        end

        opts.on("-h", "--help", "Prints this help.") do
          puts opts
          exit
        end
      end
    end

    private

    def provider_instance
      @provider_instance ||=
        begin
          case provider
          when :ssm
            Providers::Ssm.new(key_id: key_id, key_alias: key_alias)
          else
            raise ArgumentError, "Invalid provider: #{provider}"
          end
        end
    end

    def run_export(source_path, file_name, filtered: true)
      puts("Exporting #{provider}:#{source_path} to #{file_name}") if file_name.is_a?(String)

      config = fetch_config(source_path, filtered: filtered)
      write_config_file(file_name, config)
    end

    def run_import(target_path, file_name, prune, force)
      puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
      puts "+++ #{file_name}#{Colors::CLEAR}"
      config = read_config_file(file_name)
      import_config(config, target_path, prune, force)
    end

    def run_import_path(target_path, source_path, prune, force)
      puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
      puts "+++ #{provider}:#{source_path}#{Colors::CLEAR}"

      config = fetch_config(source_path, filtered: false)
      import_config(config, target_path, prune, force)

      puts("Imported #{target_path} from #{source_path} on provider: #{provider}")
    end

    def run_diff(target_path, file_name)
      source_config = read_config_file(file_name)
      source        = Utils.flatten(source_config, target_path)

      target_config = fetch_config(target_path, filtered: false)
      target        = Utils.flatten(target_config, target_path)

      if file_name.is_a?(String)
        puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
        puts "+++ #{file_name}#{Colors::CLEAR}"
      end
      diff_config(target, source)
    end

    def run_diff_path(target_path, source_path)
      source_config = fetch_config(source_path, filtered: false)
      source        = Utils.flatten(source_config)

      target_config = fetch_config(target_path, filtered: false)
      target        = Utils.flatten(target_config)

      puts "#{Colors::TITLE}--- #{provider}:#{target_path}"
      puts "+++ #{provider}:#{source_path}#{Colors::CLEAR}"

      diff_config(target, source)
    end

    def run_console
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

    def current_values(path)
      Utils.flatten(fetch_config(path, filtered: false), path)
    end

    def read_config_file(file_name)
      format = file_format(file_name)
      data   = read_file(file_name)
      parse(data, format)
    end

    def write_config_file(file_name, config)
      format = file_format(file_name)
      data   = render(config, format)
      write_file(file_name, data)
    end

    def set_config(config, path, current_values = {})
      Utils.flatten_each(config, path) do |key, value|
        next if value.nil?
        next if current_values[key].to_s == value.to_s

        if value.to_s.strip == RANDOM
          next if current_values[key]

          value = random_password
        elsif value == FILTERED
          # Ignore filtered values
          next
        end

        if current_values.key?(key)
          puts "#{Colors::KEY}* #{key}#{Colors::CLEAR}"
        else
          puts "#{Colors::ADD}+ #{key}#{Colors::CLEAR}"
        end

        provider_instance.set(key, value)
      end
    end

    def fetch_config(path, filtered: true)
      registry = Registry.new(path: path, provider: provider_instance, interpolate: interpolate)
      config   = filtered ? registry.configuration : registry.configuration(filters: nil)
      sort_hash_by_key!(config)
    end

    # Diffs two configs and displays the results
    def diff_config(target, source)
      (source.keys + target.keys).sort.uniq.each do |key|
        if target.key?(key)
          if source.key?(key)
            value = source[key].to_s
            # Ignore filtered values
            if (value != target[key].to_s) && (value != FILTERED)
              puts "#{Colors::KEY}#{key}:"
              puts "#{Colors::REMOVE}#{prefix_lines("- ", target[key])}"
              puts "#{Colors::ADD}#{prefix_lines("+ ", source[key])}#{Colors::CLEAR}\n\n"
            end
          else
            puts "#{Colors::KEY}#{key}:"
            puts "#{Colors::REMOVE}#{prefix_lines("- ", target[key])}\n\n"
          end
        elsif source.key?(key)
          puts "#{Colors::KEY}#{key}:"
          puts "#{Colors::ADD}#{prefix_lines("+ ", source[key])}#{Colors::CLEAR}\n\n"
        end
      end
    end

    def prefix_lines(prefix, value)
      value.to_s.lines.collect { |line| "#{prefix}#{line}" }.join("")
    end

    def import_config(config, path, prune, force)
      current     = current_values(path)
      delete_keys = prune ? current.keys - Utils.flatten(config, path).keys : []

      unless delete_keys.empty?
        puts "Going to delete the following keys:"
        delete_keys.each { |key| puts "  #{key}" }
        sleep(5)
      end

      set_config(config, path, force ? {} : current)

      delete_keys.each do |key|
        puts "#{Colors::REMOVE}- #{key}#{Colors::CLEAR}"
        provider_instance.delete(key)
      end
    end

    def read_file(file_name_or_io)
      return file_name_or_io.read unless file_name_or_io.is_a?(String)

      ::File.new(file_name_or_io).read
    end

    def write_file(file_name_or_io, data)
      return file_name_or_io.write(data) unless file_name_or_io.is_a?(String)

      output_path = ::File.dirname(file_name_or_io)
      FileUtils.mkdir_p(output_path) unless ::File.exist?(output_path)

      ::File.open(file_name_or_io, "w") { |io| io.write(data) }
    end

    def render(hash, format)
      case format
      when :yml
        hash.to_yaml
      when :json
        hash.to_json
      else
        raise ArgumentError, "Invalid format: #{format.inspect}"
      end
    end

    def parse(data, format)
      config =
        case format
        when :yml
          YAML.safe_load(ERB.new(data).result)
        when :json
          JSON.parse(data)
        else
          raise ArgumentError, "Invalid format: #{format.inspect}"
        end
      sort_hash_by_key!(config)
    end

    def file_format(file_name)
      return :yml unless file_name.is_a?(String)

      case File.extname(file_name).downcase
      when ".yml", ".yaml"
        :yml
      when ".json"
        :json
      else
        raise ArgumentError, "Import/Export file name must end with '.yml' or '.json'"
      end
    end

    def random_password
      SecureRandom.urlsafe_base64(random_size)
    end

    def sort_hash_by_key!(h)
      h.keys.sort.each do |key|
        value = h[key] = h.delete(key)
        sort_hash_by_key!(value) if value.is_a?(Hash)
      end
      h
    end
  end
end
