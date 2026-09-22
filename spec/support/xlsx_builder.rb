require 'zip'

# Builds an XLSX file in memory, in the shape the oil bulletin has.
#
# The real file is 4 MB, which has no place in a repository. A cassette
# of it would be worse still, because VCR stores a body as text. The
# specs therefore build their own file, which also keeps the structure
# of the format visible instead of hiding it in a binary.
module XlsxBuilder
  # `rows` is an array of arrays. A string becomes a shared string, a
  # number stays a number, and nil leaves the cell out.
  def build_xlsx(rows)
    strings = rows.flatten.compact.grep(String).uniq

    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('xl/sharedStrings.xml')
      zip.write shared_strings_xml(strings)
      zip.put_next_entry('xl/worksheets/sheet1.xml')
      zip.write sheet_xml(rows, strings)
    end.string
  end

  private

  def shared_strings_xml(strings)
    items = strings.map { |string| "<si><t>#{string}</t></si>" }.join

    %(<?xml version="1.0"?><sst count="#{strings.size}">#{items}</sst>)
  end

  def sheet_xml(rows, strings)
    body =
      rows.each_with_index.map do |cells, index|
        "<row r=\"#{index + 1}\">#{cells_xml(cells, index + 1, strings)}</row>"
      end.join

    %(<?xml version="1.0"?><worksheet><sheetData>#{body}</sheetData></worksheet>)
  end

  def cells_xml(cells, row_number, strings)
    cells.each_with_index.filter_map do |value, index|
      next if value.nil?

      reference = "#{column_name(index)}#{row_number}"
      if value.is_a?(String)
        %(<c r="#{reference}" t="s"><v>#{strings.index(value)}</v></c>)
      else
        %(<c r="#{reference}"><v>#{value}</v></c>)
      end
    end.join
  end

  # 0 becomes A, 25 becomes Z, 26 becomes AA.
  def column_name(index)
    name = +''
    index += 1
    while index.positive?
      index, remainder = (index - 1).divmod(26)
      name.prepend((remainder + 65).chr)
    end
    name
  end
end
