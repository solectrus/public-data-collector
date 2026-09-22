require 'providers/oil_bulletin/xlsx'
require 'tempfile'

describe Providers::OilBulletin::Xlsx do
  include XlsxBuilder

  subject(:xlsx) { described_class.new(file.path) }

  let(:rows) do
    [
      %w[Date DE_price_with_tax_diesel],
      [46_279, 2426.0],
      [46_272, nil]
    ]
  end

  let(:file) do
    tempfile = Tempfile.new(['spec', '.xlsx'])
    tempfile.binmode
    tempfile.write(build_xlsx(rows))
    tempfile.close
    tempfile
  end

  after { file.unlink }

  describe '#each_row' do
    it 'yields a hash of column letter to value' do
      result = []
      xlsx.each_row('xl/worksheets/sheet1.xml') { |row| result << row }

      expect(result).to eq(
        [
          { 'A' => 'Date', 'B' => 'DE_price_with_tax_diesel' },
          { 'A' => '46279', 'B' => '2426.0' },
          { 'A' => '46272' }
        ],
      )
    end

    it 'resolves the shared string table' do
      result = []
      xlsx.each_row('xl/worksheets/sheet1.xml') { |row| result << row }

      expect(result.first['B']).to eq('DE_price_with_tax_diesel')
    end
  end

  describe 'the sheet' do
    subject(:sheet) { described_class::Sheet.new(%w[Date]) }

    def rows_of(xml)
      result = []
      sheet.each_row(StringIO.new(xml.b)) { |row| result << row }
      result
    end

    it 'leaves out a cell without a value' do
      xml = '<row r="1"><c r="A1" s="5"/><c r="B1" s="5"><v>1.5</v></c><c r="C1"></c></row>'

      expect(rows_of(xml)).to eq([{ 'B' => '1.5' }])
    end

    it 'yields an empty row that closes itself' do
      xml = '<row r="1"><c r="A1" t="s"><v>0</v></c></row><row r="2" spans="1:3"/><row r="3"></row>'

      expect(rows_of(xml)).to eq([{ 'A' => 'Date' }, {}, {}])
    end

    it 'takes the value of a cell with a formula' do
      xml = '<row r="1"><c r="A1" t="str"><f>B1&amp;"x"</f><v>R&amp;D ü</v></c></row>'

      expect(rows_of(xml)).to eq([{ 'A' => 'R&D ü' }])
    end

    it 'reads a row that a chunk cuts in two' do
      stub_const("#{described_class}::Sheet::CHUNK_SIZE", 7)
      rows = (1..20).map { |i| %(<row r="#{i}"><c r="A#{i}"><v>#{i}</v></c><c r="B#{i}"/></row>) }
      xml = "<sheetData>#{rows.join}"

      expect(rows_of(xml)).to eq((1..20).map { |i| { 'A' => i.to_s } })
    end
  end

  context 'without a shared string table' do
    let(:rows) { [[1, 2]] }

    it 'reads the numbers anyway' do
      # A file of numbers alone carries no string table
      result = []
      xlsx.each_row('xl/worksheets/sheet1.xml') { |row| result << row }

      expect(result).to eq([{ 'A' => '1', 'B' => '2' }])
    end
  end
end
