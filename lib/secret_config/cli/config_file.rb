require "fileutils"
require "erb"
require "yaml"
require "json"

module SecretConfig
  class CLI
    # The YAML or JSON file that --export, --import and --diff transfer to or from.
    #
    # Distinct from `Providers::File`, which is a store that the CLI reads and writes through the
    # provider interface. This is a flat document handed to, or received from, the user.
    class ConfigFile
      # `file_name_or_io` is a path, or the IO that --export and --import fall back to when no
      # --file is supplied: $stdout and $stdin respectively.
      def initialize(file_name_or_io)
        @file_name_or_io = file_name_or_io
      end

      def read
        parse(read_data)
      end

      def write(config)
        write_data(render(config))
      end

      private

      attr_reader :file_name_or_io

      def read_data
        return file_name_or_io.read unless file_name_or_io.is_a?(String)

        ::File.new(file_name_or_io).read
      end

      # An export holds the real values whenever `--no-filter` was supplied, so a file created here is
      # readable only by its owner. Writing to an IO is left alone: where $stdout goes is the caller's.
      def write_data(data)
        return file_name_or_io.write(data) unless file_name_or_io.is_a?(String)

        output_path = ::File.dirname(file_name_or_io)
        FileUtils.mkdir_p(output_path)

        Utils.write_private_file(file_name_or_io, data)
      end

      # `format` raises for anything it does not recognize, so both of these only ever see the two
      # formats below.
      def render(config)
        format == :json ? config.to_json : config.to_yaml
      end

      # A YAML transfer file is passed through ERB, the same way `Providers::File` treats the file it
      # reads, and the same way Rails treats `database.yml`. `--diff` evaluates it too, deliberately:
      # a diff exists to show what an import will do, so it has to evaluate whatever the import will.
      #
      # This does mean a transfer file is code, and running either command on one is choosing to run
      # it. That is a documented property rather than something to gate behind a flag; the file is
      # normally one you wrote, in your own repository or deploy tooling.
      def parse(data)
        config = format == :json ? JSON.parse(data) : YAML.safe_load(ERB.new(data).result)
        Utils.sort_by_key!(config)
      end

      # An IO has no name to infer a format from, so stdin and stdout are always YAML.
      def format
        return :yml unless file_name_or_io.is_a?(String)

        case ::File.extname(file_name_or_io).downcase
        when ".yml", ".yaml"
          :yml
        when ".json"
          :json
        else
          raise ArgumentError, "Import/Export file name must end with '.yml' or '.json'"
        end
      end
    end
  end
end
