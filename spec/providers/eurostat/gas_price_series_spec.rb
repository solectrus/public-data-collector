require 'providers/eurostat/gas_price_series'
require 'providers/eurostat/settings'

describe Providers::Eurostat::GasPriceSeries do
  subject(:gas_price_series) { described_class.new(Providers::Eurostat::Settings.from_env) }

  def stub_eurostat(body)
    stub_request(:get, /ec\.europa\.eu/).to_return(
      status: 200,
      body: JSON.generate(body),
      headers: { 'Content-Type' => 'application/json' },
    )
  end

  # JSON-stat as Eurostat answers it: one flat list of values, keyed by the
  # position in the grid of all dimensions.
  def json_stat(periods, values, sizes: nil)
    {
      id: %w[freq siec nrg_cons unit tax currency geo time],
      size: sizes || [1, 1, 1, 1, 1, 1, 1, periods.size],
      value: values,
      dimension: { time: { category: { index: periods } } },
    }
  end

  # The first day of every month in the range
  def months(year, range)
    range.map { |month| Time.new(year, month, 1) }
  end

  def months_between(first, last)
    (first.to_date..last.to_date).select { |date| date.day == 1 }.map(&:to_time)
  end

  describe '#records' do
    context 'with a recorded answer of the API' do
      it 'returns the half years and carries the newest one forward' do
        prices = VCR.use_cassette('eurostat/gas_prices') { gas_price_series.records }

        expect(prices.size).to be > 40
        expect(prices.map(&:amount)).to all(be_a(Numeric))

        # One value per month without a gap: the half years fill their six
        # months, the carried months follow the newest half year
        starts = prices.map(&:starts_at).sort
        expect(starts.first).to eq(Time.new(2007, 7, 1))
        expect(starts.last).to eq(Time.new(2026, 8, 1))
        expect(starts).to eq(months_between(starts.first, starts.last))
        expect(starts.last).to be > Time.new(2026, 1, 1)
      end
    end

    it 'writes a first half year into January to June' do
      stub_eurostat(json_stat({ '2025-S1' => 0 }, { '0' => 0.1216 }))

      prices = gas_price_series.records

      expect(prices.map(&:starts_at)).to eq(months(2025, 1..6))
      expect(prices.map(&:amount)).to all(eq(0.1216))
    end

    # Integer reads "08" and "09" as octal numbers without the base 10
    it 'carries August and September forward' do
      stub_eurostat(json_stat({ '2025-S2' => 0 }, { '0' => 0.12 }))
      index = { '2025-07' => 0, '2025-12' => 1, '2026-08' => 2, '2026-09' => 3 }
      stub_request(:get, /prc_hicp_minr/).to_return(
        status: 200,
        body: JSON.generate(json_stat(index, { '0' => 100, '1' => 100, '2' => 110, '3' => 90 })),
      )

      prices = gas_price_series.records

      expect(prices.last(2).map(&:starts_at)).to eq(months(2026, 8..9))
    end

    it 'writes a second half year into July to December' do
      stub_eurostat(json_stat({ '2025-S2' => 0 }, { '0' => 0.1223 }))

      prices = gas_price_series.records

      expect(prices.map(&:starts_at)).to eq(months(2025, 7..12))
    end

    # Once Eurostat publishes a half year, its measured price replaces the
    # carried points that earlier reads wrote into its months
    it 'carries the newest half year forward after its six months' do
      stub_eurostat(json_stat({ '2025-S2' => 0 }, { '0' => 0.12 }))
      index = { '2025-07' => 0, '2025-12' => 1, '2026-01' => 2, '2026-02' => 3 }
      stub_request(:get, /prc_hicp_minr/).to_return(
        status: 200,
        body: JSON.generate(json_stat(index, { '0' => 100, '1' => 100, '2' => 110, '3' => 90 })),
      )

      prices = gas_price_series.records

      expect(prices.map(&:starts_at)).to eq(months(2025, 7..12) + months(2026, 1..2))
      expect(prices.map(&:amount)).to eq(([0.12] * 6) + [0.132, 0.108])
    end

    it 'keeps the half years when the index fails, and warns' do
      stub_eurostat(json_stat({ '2025-S2' => 0 }, { '0' => 0.1223 }))
      stub_request(:get, /prc_hicp_minr/).to_return(status: 500)

      prices = nil
      stdout, = capture_output { prices = gas_price_series.records }

      expect(prices.map(&:starts_at)).to eq(months(2025, 7..12))
      expect(stdout).to include('! 500')
      expect(stdout).to include('the newest gas price is not carried forward')
    end

    it 'asks for the configured country and the household consumption band' do
      stub_eurostat(json_stat({ '2025-S2' => 0 }, { '0' => 0.1 }))

      gas_price_series.records

      expect(
        a_request(:get, /ec\.europa\.eu/).with(
          query: hash_including(
            geo: 'DE',
            nrg_cons: described_class::CONSUMPTION_BAND,
            tax: described_class::TAX_LEVEL,
            unit: 'KWH',
            currency: 'EUR',
          ),
        ),
      ).to have_been_made
    end

    it 'asks for Greece in the spelling of Eurostat' do
      stub_eurostat(json_stat({ '2025-S2' => 0 }, { '0' => 0.1 }))

      with_env(COUNTRY: 'GR') { gas_price_series.records }

      expect(a_request(:get, /ec\.europa\.eu/).with(query: hash_including(geo: 'EL'))).to have_been_made.twice
    end

    it 'skips a half year without a value' do
      stub_eurostat(json_stat({ '2025-S1' => 0, '2025-S2' => 1 }, { '1' => 0.1223 }))

      prices = gas_price_series.records

      expect(prices.map(&:starts_at)).to eq(months(2025, 7..12))
    end

    it 'skips a period it cannot read' do
      stub_eurostat(json_stat({ '2025-S3' => 0, '2025-S2' => 1 }, { '0' => 0.1, '1' => 0.1223 }))

      prices = gas_price_series.records

      expect(prices.map(&:starts_at)).to eq(months(2025, 7..12))
    end

    it 'skips a year it cannot read' do
      stub_eurostat(json_stat({ 'later-S1' => 0 }, { '0' => 0.1 }))

      prices = gas_price_series.records

      expect(prices).to be_empty
    end

    describe 'error handling' do
      it 'refuses an answer that holds more than one series' do
        stub_eurostat(json_stat({ '2025-S2' => 0 }, { '0' => 0.1 }, sizes: [1, 1, 2, 1, 1, 1, 1, 1]))

        prices = gas_price_series.records

        expect(prices).to be_empty
      end

      it 'refuses an answer without the dimensions' do
        stub_eurostat({ value: { '0' => 0.1 } })

        prices = gas_price_series.records

        expect(prices).to be_empty
      end

      it 'reports an answer that is not JSON' do
        stub_request(:get, /ec\.europa\.eu/).to_return(status: 200, body: 'not json')

        expect { gas_price_series.records }.to raise_error(Providers::FetchError, /cannot parse the answer/)
      end

      it 'reports a server error' do
        stub_request(:get, /ec\.europa\.eu/).to_return(status: 500)

        expect { gas_price_series.records }.to raise_error(Providers::FetchError, /500/)
      end
    end
  end

  describe '#fetch' do
    it 'sums up the newest value' do
      _, summary = VCR.use_cassette('eurostat/gas_prices') { gas_price_series.fetch }

      expect(summary).to match(%r{\A\d+ values, latest [\d.]+ ct/kWh for \d{4}-\d{2}\z})
    end

    it 'refuses an unknown country, which Eurostat answers with no values' do
      stub_eurostat(json_stat({ '2025-S2' => 0 }, {}, sizes: [1, 1, 1, 1, 1, 1, 0, 38]))

      expect { gas_price_series.fetch }.to raise_error(Providers::FetchError, 'no prices for country "DE"')
    end
  end
end
