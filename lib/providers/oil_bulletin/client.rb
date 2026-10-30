require 'date'
require 'tempfile'
require 'uri'

require 'providers/country'
require 'providers/http'
require 'providers/oil_bulletin/xlsx'

module Providers
  module OilBulletin
    NAME = 'EU Weekly Oil Bulletin'.freeze

    # The measurement of the fuel prices.
    MEASUREMENT = 'Fuel'.freeze

    # Downloads the price history and reads it.
    #
    # The answer is an XLSX file of about 4 MB. It carries no ETag and no
    # Last-Modified, so a conditional request is not possible and every
    # read downloads all of it. The collector therefore reads it once a
    # week.
    #
    # This is not a JsonApi subclass: the answer is a spreadsheet, not JSON.
    class Client
      # The page that links the file. The link carries a UUID. It stayed the
      # same through 2026 while the file changed every week, but nothing
      # promises that, so the collector reads the page and looks the link up
      # by its file name.
      PAGE_URL = 'https://energy.ec.europa.eu/data-and-analysis/weekly-oil-bulletin_en'.freeze

      # The name of the file that holds the whole history. The page links
      # several others: one week with taxes, one week without, the duties,
      # and a methodology note per country.
      FILE_NAME = 'Weekly_Oil_Bulletin_Prices_History'.freeze

      LINK_PATTERN = %r{href="(/document/download/[^"]*filename=#{FILE_NAME}[^"]*)"}

      # The first sheet holds the prices a consumer pays, taxes included.
      SHEET = 'xl/worksheets/sheet1.xml'.freeze

      # The column that holds the date of the week.
      DATE_COLUMN = 'A'.freeze

      # Every row as {date, prices}, where prices maps a product name to the
      # price in euro per 1000 litres.
      Week = Data.define(:date, :prices)

      # The bulletin names its columns with the ISO code, so the country
      # is stored in that spelling.
      def initialize(country:)
        @country = Country.iso(country)
      end

      attr_reader :country

      # The weeks the file holds. Raises FetchError when the download or the
      # file failed.
      def weeks
        download do |path|
          read(path)
        end
      end

      private

      # Downloads into a temporary file and removes it afterwards. The file
      # is too large to keep in a string while a ZIP reader seeks through it,
      # so the body goes to the file chunk by chunk.
      def download
        file = Tempfile.new(['oil-bulletin', '.xlsx'])
        begin
          file.binmode
          Http.download(file_url, file, source: NAME)
          file.close
          yield file.path
        ensure
          file.unlink
        end
      end

      # Looks the file up on the page. A page that no longer names the file
      # fails the read, so that a redesign of the website shows in the log.
      def file_url
        page = Http.get(URI(PAGE_URL), source: "the page of #{NAME}")
        path = page[LINK_PATTERN, 1] or raise FetchError, "the page of #{NAME} names no #{FILE_NAME}"

        URI.join(PAGE_URL, path)
      end

      # The first row names every column. The rows after it hold the data,
      # except for two rows with the product names and the units. Those
      # carry no date and no price, so week_of skips them.
      def read(path)
        columns = nil
        weeks = []

        Xlsx.new(path).each_row(SHEET) do |row|
          if columns
            week = week_of(row, columns)
            weeks << week if week
          else
            columns = columns_of(row)
            raise FetchError, "#{NAME} holds no country #{country.inspect}" if columns.empty?
          end
        end

        weeks
      rescue Zip::Error, REXML::ParseException => e
        raise FetchError, "cannot read the file of #{NAME} (#{e.message})"
      end

      # The columns of the configured country, as {column letter => product}.
      # A header reads "DE_price_with_tax_diesel".
      def columns_of(header)
        prefix = "#{country}_price_with_tax_"

        header.filter_map do |column, name|
          [column, name.delete_prefix(prefix)] if name.to_s.start_with?(prefix)
        end.to_h
      end

      def week_of(row, columns)
        date = date_of(row[DATE_COLUMN])
        return unless date

        prices = columns.filter_map do |column, product|
          amount = Float(row[column].to_s, exception: false)
          [product, amount] if amount&.positive?
        end.to_h

        Week.new(date, prices) unless prices.empty?
      end

      # A date arrives as a serial number, counted from the last day of 1899
      # as every spreadsheet does.
      def date_of(value)
        serial = Integer(value.to_s[/\A\d+/].to_s, 10, exception: false)
        return unless serial

        Date.new(1899, 12, 30) + serial
      end
    end
  end
end
