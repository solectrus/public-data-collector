require 'rexml/parsers/pullparser'
require 'rexml/text'
require 'zip'

module Providers
  module OilBulletin
    # Reads one sheet of an XLSX file, row by row.
    #
    # An XLSX file is a ZIP archive of XML documents. The sheet of the oil
    # bulletin is about 9 MB once unpacked, which is too much to hold in
    # memory on the small machines this collector runs on. This class
    # therefore streams: it reads the sheet in chunks and hands over one
    # row at a time, and never builds a tree.
    class Xlsx
      SHARED_STRINGS = 'xl/sharedStrings.xml'.freeze

      def initialize(path)
        @path = path
      end

      attr_reader :path

      # Yields every row of a sheet as a hash of column letter to value, for
      # example {"A" => "46279", "B" => "EU_"}. Empty cells are absent.
      def each_row(sheet, &)
        Zip::File.open(path) do |zip|
          strings = read_shared_strings(zip)
          Sheet.new(strings).each_row(zip.get_entry(sheet).get_input_stream, &)
        end
      end

      private

      # XLSX keeps text in one shared table and puts an index into the cell.
      # Reading the table first lets a cell answer with its text.
      def read_shared_strings(zip)
        entry = zip.find_entry(SHARED_STRINGS)
        entry ? shared_strings(entry.get_input_stream) : []
      end

      # The text of every `si` element, in the order of the table. The table
      # is small, but its text can carry entities and rich text runs, so it
      # goes through a real XML parser.
      def shared_strings(stream)
        strings = []
        current = nil

        each_event(stream) do |event|
          case event.event_type
          when :start_element then strings << (current = +'') if event[0] == 'si'
          when :text then current&.<<(event[1])
          when :end_element then current = nil if event[0] == 'si'
          end
        end

        strings
      end

      # Pulls the XML one token at a time. Every token is a REXML pull
      # event: a start element carries its name and its attributes, a text
      # carries its value at index 1, an end element carries its name.
      def each_event(stream)
        parser = REXML::Parsers::PullParser.new(stream)

        yield parser.pull while parser.has_next?
      end

      # Builds one row at a time out of the chunks of a sheet.
      #
      # A sheet holds nothing but rows of cells, each with at most one value,
      # in a shape that every spreadsheet writes the same way. A pattern for
      # that shape does the work of an XML parser with far less garbage. For
      # the sheet of the oil bulletin, REXML took 9 seconds and a peak of
      # 100 MB in the container, this class takes 0.5 seconds and 55 MB.
      class Sheet
        CHUNK_SIZE = 64 * 1024

        # A row with its cells, or an empty row that closes itself
        ROW = %r{<row\b[^>]*?(?:/>|>(.*?)</row>)}m

        # A cell with its attributes and its content, or an empty cell
        CELL = %r{<c\b([^>]*?)(?:/>|>(.*?)</c>)}m

        VALUE = %r{<v>([^<]*)</v>}
        COLUMN = /\br="([A-Z]+)/
        TYPE = /\bt="([^"]*)"/

        def initialize(strings)
          @strings = strings
        end

        attr_reader :strings

        # A row that a chunk cuts in two stays in the buffer until the next
        # chunk completes it. The buffer is binary, so a cut through a
        # multibyte character cannot break the pattern.
        def each_row(stream)
          buffer = String.new(encoding: Encoding::BINARY)

          while (chunk = stream.read(CHUNK_SIZE))
            buffer << chunk
            consumed = 0

            buffer.scan(ROW) do
              consumed = Regexp.last_match.end(0)
              yield row(Regexp.last_match(1))
            end

            buffer = buffer.byteslice(consumed..) if consumed.positive?
          end
        end

        private

        def row(cells)
          result = {}

          cells&.scan(CELL) do |attributes, content|
            value = content && content[VALUE, 1]
            next unless value

            result[attributes[COLUMN, 1]] = cell_value(value, attributes[TYPE, 1])
          end

          result
        end

        def cell_value(value, type)
          return strings[value.to_i] if type == 's'

          value.force_encoding(Encoding::UTF_8)
          value.include?('&') ? REXML::Text.unnormalize(value) : value
        end
      end
    end
  end
end
