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

      def parse(data)
        config = format == :json ? JSON.parse(data) : YAML.safe_load(evaluate_erb(data))
        Utils.sort_by_key!(config)
      end

      # A transfer file is data, and usually data that came from somewhere else: an export from a
      # colleague, an artifact built in CI, something piped in on stdin. Evaluating ERB in it runs
      # whatever code it contains, on `--diff` as much as on `--import`, and nothing documents that it
      # happens at all. The next major release will require an explicit `--erb`, so warn while
      # evaluating is still the default.
      def evaluate_erb(data)
        if data.match?(/<%/)
          SecretConfig.deprecation_warning(
            "ERB in #{source_description} is evaluated, which runs whatever code the file contains. " \
            "The next major release will not evaluate it without an explicit `--erb`. " \
            "Remove the ERB, or be ready to supply that option."
          )
        end

        ERB.new(data).result
      end

      def source_description
        file_name_or_io.is_a?(String) ? "import file #{file_name_or_io}" : "the import read from stdin"
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
