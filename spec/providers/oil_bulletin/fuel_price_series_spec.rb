require 'date'

require 'providers/oil_bulletin/fuel_price_series'
require 'providers/oil_bulletin/settings'

describe Providers::OilBulletin::FuelPriceSeries do
  include XlsxBuilder

  subject(:fuel_price_series) { described_class.new(Providers::OilBulletin::Settings.from_env) }

  # Row 1 names the columns, rows 2 and 3 carry the product names and
  # the units, row 4 onwards holds the data. A date is a serial number
  # counted from the last day of 1899.
  def bulletin(rows, country: 'DE')
    header = ['Date', *%w[euro95 diesel heating_oil LPG].map { |p| "#{country}_price_with_tax_#{p}" }]

    build_xlsx([header, ['', nil, nil, nil, nil], ['Date', '1000 l', '1000 l', '1000 l', '1000 l'], *rows])
  end

  # The page is replayed from a cassette, so the link lookup runs against
  # the real page. A spec that stubs the page itself overrides it.
  around { |example| VCR.use_cassette('oil_bulletin/page', &example) }

  def stub_bulletin(body)
    stub_request(:get, %r{energy\.ec\.europa\.eu/document/download}).to_return(status: 200, body:)
  end

  describe '#records' do
    it 'reads one week per row and divides by 1000 litres' do
      stub_bulletin(bulletin([[46_279, 2357.0, 2426.0, 1683.0, 1086.5]]))

      prices = fuel_price_series.records

      expect(prices.size).to eq(1)
      expect(prices.first).to have_attributes(
        starts_at: Time.new(2026, 9, 14),
        petrol: 2.357,
        diesel: 2.426,
        heating_oil: 1.683,
        lpg: 1.087,
      )
    end

    # XLSX leaves out an empty row, so the data can start in any row
    it 'reads the first week when the rows of names and units are absent' do
      header = ['Date', *%w[euro95 diesel heating_oil LPG].map { |p| "DE_price_with_tax_#{p}" }]
      stub_bulletin(build_xlsx([header, [46_279, 2357.0, 2426.0, 1683.0, 1086.5]]))

      expect(fuel_price_series.records.map(&:starts_at)).to eq([Time.new(2026, 9, 14)])
    end

    it 'leaves out a product the country does not report' do
      stub_bulletin(bulletin([[46_279, 2357.0, 2426.0, nil, nil]]))

      prices = fuel_price_series.records

      expect(prices.first).to have_attributes(petrol: 2.357, heating_oil: nil, lpg: nil)
    end

    it 'reads the whole history' do
      weeks = (0...200).map { |i| [46_279 - (i * 7), 2000.0 + i, 2100.0 + i, nil, nil] }
      stub_bulletin(bulletin(weeks))

      prices = fuel_price_series.records

      expect(prices.size).to eq(200)

      # 199 weeks before 2026-09-14, counted in days and not in seconds:
      # the span crosses the switch to winter time
      oldest = Date.new(2026, 9, 14) - (199 * 7)
      expect(prices.map(&:starts_at).min).to eq(Time.new(oldest.year, oldest.month, oldest.day))
    end

    it 'skips a row without a date' do
      stub_bulletin(bulletin([['', 2357.0, nil, nil, nil], [46_279, 2357.0, nil, nil, nil]]))

      prices = fuel_price_series.records

      expect(prices.size).to eq(1)
    end

    it 'skips a week in which every price is missing' do
      stub_bulletin(bulletin([[46_272, nil, nil, nil, nil], [46_279, 2357.0, nil, nil, nil]]))

      prices = fuel_price_series.records

      expect(prices.size).to eq(1)
    end

    it 'asks the page for the file and follows the link it names' do
      stub_bulletin(bulletin([[46_279, 2357.0, nil, nil, nil]]))

      fuel_price_series.records

      expect(a_request(:get, %r{/document/download/.*filename=Weekly_Oil_Bulletin_Prices_History})).to have_been_made
    end

    describe 'error handling' do
      it 'reports the rate limit with the time to wait' do
        stub_request(:get, /energy\.ec\.europa\.eu/).to_return(status: 429, headers: { 'Retry-After' => '30' })

        capture_output do
          expect { fuel_price_series.records }
            .to raise_error(Providers::FetchError, /rate limit reached, retry after 30 seconds/)
        end
      end

      it 'reports a connection that does not answer' do
        stub_request(:get, /energy\.ec\.europa\.eu/).to_timeout

        expect { fuel_price_series.records }.to raise_error(Providers::FetchError)
      end

      it 'reports a country the bulletin does not hold' do
        stub_bulletin(bulletin([[46_279, 2357.0, nil, nil, nil]], country: 'FR'))

        expect { fuel_price_series.records }.to raise_error(Providers::FetchError, /holds no country "DE"/)
      end

      it 'reports a page that does not name the file' do
        stub_request(:get, %r{energy\.ec\.europa\.eu/data-and-analysis}).to_return(status: 200, body: '<html></html>')

        expect { fuel_price_series.records }
          .to raise_error(Providers::FetchError, /names no Weekly_Oil_Bulletin_Prices_History/)
        expect(a_request(:get, %r{/document/download})).not_to have_been_made
      end

      it 'reports a file it cannot read' do
        stub_bulletin('this is not a zip archive')

        expect { fuel_price_series.records }.to raise_error(Providers::FetchError, /cannot read the file/)
      end

      it 'reports a server error' do
        stub_request(:get, %r{energy\.ec\.europa\.eu/document/download}).to_return(status: 500)

        expect { fuel_price_series.records }.to raise_error(Providers::FetchError, /500/)
      end
    end
  end

  describe '#fetch' do
    it 'sums up the weeks and the newest prices' do
      stub_bulletin(bulletin([[46_272, 2300.0, 2400.0, nil, nil], [46_279, 2357.0, 2426.0, nil, nil]]))

      _, summary = fuel_price_series.fetch

      expect(summary).to eq('2 weeks, latest 2026-09-14: petrol 2.357, diesel 2.426 EUR/l')
    end

    it 'refuses a bulletin that holds no usable week' do
      stub_bulletin(bulletin([[46_279, nil, nil, nil, nil]]))

      expect { fuel_price_series.fetch }.to raise_error(Providers::FetchError, 'no prices for country "DE"')
    end
  end
end
