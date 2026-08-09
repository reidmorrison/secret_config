require "optparse"

module SecretConfig
  class CLI
    # The command line options, and the OptionParser that populates them.
    #
    # Held separately from `CLI` so that the option definitions can be read as a list, and so that
    # the command implementations are not mixed in with the parsing. `CLI` delegates a reader for
    # every option, so `SecretConfig::CLI.new(argv).provider` still answers.
    class Options
      attr_reader :path, :provider, :file_name, :provider_file,
                  :export, :no_filter, :interpolate,
                  :import, :key_id, :key_alias, :random_size, :prune, :force,
                  :fetch_key, :delete_key, :set_key, :set_value, :delete_tree,
                  :diff,
                  :console,
                  :show_version

      def initialize(argv)
        @export        = false
        @import        = false
        @path          = nil
        @file_name     = nil
        @key_id        = nil
        @key_alias     = nil
        @provider      = :ssm
        @provider_file = nil
        @random_size   = 32
        @no_filter     = false
        @prune         = false
        @show_version  = false
        @console       = false
        @diff          = false
        @set_key       = nil
        @set_value     = nil
        @fetch_key     = nil
        @delete_key    = nil
        @delete_tree   = nil
        @force         = false
        @interpolate   = false

        if argv.empty?
          puts parser
          exit(-10)
        end
        parser.parse!(argv)
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = <<~BANNER
            Secret Config v#{VERSION}

              For more information, see: https://config.reidmorrison.com/

            secret-config [options]
          BANNER

          define_transfer_options(opts)
          define_key_options(opts)
          define_provider_options(opts)
          define_modifier_options(opts)
          define_general_options(opts)
        end
      end

      private

      # The operations that move a whole tree: --export, --import and --diff, and the file and path
      # they move it to or from.
      def define_transfer_options(opts)
        opts.on "-e", "--export SOURCE_PATH",
                "Export configuration. Use --file to specify the file name, otherwise stdout is used." do |path|
          @export = path
        end

        opts.on "-i", "--import TARGET_PATH",
                "Import configuration. Use --file to specify the file name, --path for the SOURCE_PATH, " \
                "otherwise stdin is used." do |path|
          @import = path
        end

        opts.on "--diff TARGET_PATH",
                "Compare configuration to this path. Use --file to specify the source file name, " \
                "--path for the SOURCE_PATH, otherwise stdin is used." do |file_name|
          @diff = file_name
        end

        # No short option: "-f" belongs to --fetch below.
        opts.on "--file FILE_NAME", "Import/Export/Diff to/from this file." do |file_name|
          @file_name = file_name
        end

        opts.on "-p", "--path PATH", "Import/Export/Diff to/from this path." do |path|
          @path = path
        end
      end

      # The operations that act on one key, or on one subtree.
      def define_key_options(opts)
        opts.on "-s", "--set KEY=VALUE", "Set one key to value. Example: --set mysql/database=localhost" do |param|
          # Split on the first "=" only, so that values containing "=" are preserved.
          # For example base64 encoded encryption keys, which are padded with "=".
          @set_key, @set_value = param.split("=", 2)
          if @set_key.to_s.empty? || @set_value.to_s.empty?
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
      end

      # Which store to talk to, and how it encrypts what is written to it.
      def define_provider_options(opts)
        opts.on "--provider PROVIDER", "Provider to use. [ssm | secrets_manager | file]. Default: ssm" do |provider|
          @provider = provider.to_sym
        end

        # Distinct from --file, which is the file that --export/--import/--diff transfer to or from.
        # This is the store itself, the file provider's equivalent of the SSM parameter tree.
        opts.on "--provider-file FILE_NAME",
                "For --provider file only. The config file to read and write. " \
                "Default: $SECRET_CONFIG_FILE_NAME, then config/application.yml." do |file_name|
          @provider_file = file_name
        end

        opts.on "--key_id KEY_ID",
                "For --import only. Encrypt config settings with this AWS KMS key id. Default: AWS Default key." do |key_id|
          @key_id = key_id
        end

        opts.on "--key_alias KEY_ALIAS", "For --import only. Encrypt config settings with this AWS KMS alias." do |key_alias|
          @key_alias = key_alias
        end
      end

      # Flags that change how an --export or an --import behaves.
      def define_modifier_options(opts)
        opts.on "--no-filter", "For --export only. Do not filter passwords and keys." do
          @no_filter = true
        end

        opts.on "--interpolate", "For --export only. Evaluate string interpolation and __import__." do
          @interpolate = true
        end

        opts.on "--prune",
                "For --import only. During import delete all existing keys for which there is no key " \
                "in the import file. Only works with --import." do
          @prune = true
        end

        opts.on "--force",
                "For --import only. Overwrite all values, not just the changed ones. Useful for changing the KMS key." do
          @force = true
        end

        opts.on "--random_size INTEGER", Integer,
                "Deprecated. For --import only. Default size in bytes to use when generating values " \
                "when __generate__ is encountered in the source. Supply the size on each value instead, " \
                "as __generate__:size. Default: 32" do |random_size|
          SecretConfig.deprecation_warning(
            "`--random_size` is deprecated. Supply the size on each value instead, as " \
            "`#{SecretConfig::GENERATE}:#{random_size}`, which sets it per key rather than for the whole import."
          )
          @random_size = random_size
        end
      end

      def define_general_options(opts)
        opts.on "-c", "--console", "Start interactive console." do
          @console = true
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
  end
end
