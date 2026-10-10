require 'providers/energy_charts/price_series'
require 'providers/energy_charts/settings'

describe Providers::EnergyCharts::PriceSeries do
  subject(:price_series) { described_class.new(Providers::EnergyCharts::Settings.from_env) }

  def stub_price_request(body)
    stub_request(:get, /api\.energy-charts\.info/).to_return(
      status: 200,
      body: JSON.generate(body),
      headers: { 'Content-Type' => 'application/json' },
    )
  end

  describe '#records' do
    context 'with a recorded answer of the API' do
      it 'returns a price for every quarter hour' do
        prices = VCR.use_cassette('energy_charts/price') { price_series.records }

        expect(prices).not_to be_empty
        expect(prices.map { |price| price.starts_at.localtime.min }.uniq).to contain_exactly(0, 15, 30, 45)
        expect(prices.map(&:amount)).to all(be_a(Numeric))
      end
    end

    it 'converts the price per MWh to a price per kWh' do
      stub_price_request(
        unit: 'EUR / MWh',
        data: [{ timestamp: '2026-09-19T00:00:00+02:00', values: { day_ahead_price: 132.52 } }],
      )

      prices = price_series.records

      expect(prices.size).to eq(1)
      expect(prices.first).to have_attributes(
        amount: 0.13252,
        starts_at: Time.new(2026, 9, 19, 0, 0, 0, '+02:00'),
      )
    end

    it 'skips an interval without a price' do
      stub_price_request(
        unit: 'EUR / MWh',
        data: [
          { timestamp: '2026-09-19T00:00:00+02:00', values: { day_ahead_price: nil } },
          { timestamp: '2026-09-19T00:15:00+02:00', values: { day_ahead_price: 100.0 } }
        ],
      )

      prices = price_series.records

      expect(prices.size).to eq(1)
      expect(prices.first.amount).to eq(0.1)
    end

    it 'asks for today and tomorrow' do
      stub_price_request(unit: 'EUR / MWh', data: [])

      price_series.records

      today = Time.now.to_date
      expect(
        a_request(:get, /api\.energy-charts\.info/).with(
          query: { bzn: 'DE-LU', start: today.to_s, end: (today + 1).to_s },
        ),
      ).to have_been_made
    end

    describe 'error handling' do
      it 'refuses a unit that is not a price per MWh' do
        stub_price_request(unit: 'EUR / kWh', data: [])

        expect { price_series.records }.to raise_error(Providers::FetchError, /unexpected unit/)
      end

      it 'returns no prices for an answer without prices' do
        stub_price_request(unit: 'EUR / MWh', data: [])

        prices = price_series.records

        expect(prices).to be_empty
      end

      it 'reports an answer that is not JSON' do
        stub_request(:get, /api\.energy-charts\.info/).to_return(status: 200, body: 'not json')

        expect { price_series.records }.to raise_error(Providers::FetchError, /cannot parse the answer/)
      end

      it 'reports a server error' do
        stub_request(:get, /api\.energy-charts\.info/).to_return(status: 500)

        expect { price_series.records }.to raise_error(Providers::FetchError, /500/)
      end

      it 'reports the rate limit with the time to wait' do
        stub_request(:get, /api\.energy-charts\.info/)
          .to_return(status: 429, headers: { 'Retry-After' => '30' })

        expect do
          price_series.records
        end.to raise_error(Providers::FetchError, /rate limit reached, retry after 30 seconds/)
      end

      # A 503 is maintenance or overload, not the rate limit of the user
      it 'reports an unavailable service as such' do
        stub_request(:get, /api\.energy-charts\.info/).to_return(status: [503, 'Service Unavailable'])

        expect do
          price_series.records
        end.to raise_error(Providers::FetchError, '503 Service Unavailable from Energy-Charts')
      end

      it 'reports a connection that does not answer' do
        stub_request(:get, /api\.energy-charts\.info/).to_timeout

        expect { price_series.records }.to raise_error(Providers::FetchError)
      end
    end
  end

  describe '#since' do
    let(:now) { Time.local(2026, 10, 10, 12) }

    before { allow(Time).to receive(:now).and_return(now) }

    it 'writes the history at the first read' do
      expect(price_series.since(Time.local(2020, 11, 27), first_read: true)).to eq(Time.local(2020, 11, 27))
    end

    it 'writes the current answer alone at every later read' do
      expect(price_series.since(Time.local(2020, 11, 27), first_read: false)).to be_nil
    end

    # The bucket holds no other data, or the token may not read
    it 'writes the current answer alone for a start within today' do
      expect(price_series.since(now, first_read: true)).to be_nil
    end

    it 'writes the current answer alone without a start' do
      expect(price_series.since(nil, first_read: true)).to be_nil
    end
  end

  describe 'the history' do
    before do
      allow(Time).to receive(:now).and_return(Time.local(2026, 10, 10, 12))
      stub_const('Providers::EnergyCharts::Client::SPACING', 0)
    end

    # One price at the start of the first day
    def stub_prices(first, last, status: 200)
      data = [{ timestamp: Date.parse(first).to_time.iso8601, values: { day_ahead_price: 100.0 } }]

      stub_request(:get, 'https://api.energy-charts.info/v2/price')
        .with(query: { bzn: 'DE-LU', start: first, end: last })
        .to_return(status:, body: JSON.generate(unit: 'EUR / MWh', data:))
    end

    it 'reads the days before today a year at a time, then today and tomorrow' do
      requests = [
        stub_prices('2025-10-10', '2026-10-09'),
        stub_prices('2024-10-10', '2025-10-09'),
        stub_prices('2024-06-15', '2024-10-09'),
        stub_prices('2026-10-10', '2026-10-11')
      ]

      batch, summary = price_series.fetch(Time.local(2024, 6, 15, 8))

      expect(requests).to all(have_been_requested.once)
      expect(batch.rows.map(&:time)).to eq(
        [Time.local(2024, 6, 15), Time.local(2024, 10, 10), Time.local(2025, 10, 10), Time.local(2026, 10, 10)],
      )
      expect(summary).to eq('4 prices (from 2024-06-15)')
    end

    it 'ends the history at an older year that has no data' do
      stub_prices('2025-10-10', '2026-10-09')
      stub_prices('2024-10-10', '2025-10-09', status: 404)
      stub_prices('2026-10-10', '2026-10-11')

      batch, = price_series.fetch(Time.local(2018, 1, 1))

      expect(batch.rows.map(&:time)).to contain_exactly(Time.local(2025, 10, 10), Time.local(2026, 10, 10))
    end

    it 'fails when the newest year fails' do
      stub_prices('2025-10-10', '2026-10-09', status: 404)

      expect { price_series.fetch(Time.local(2018, 1, 1)) }.to raise_error(Providers::FetchError, /404/)
    end

    it 'fails when an older year fails for another reason' do
      stub_prices('2025-10-10', '2026-10-09')
      stub_prices('2024-10-10', '2025-10-09', status: 500)

      expect { price_series.fetch(Time.local(2024, 1, 1)) }.to raise_error(Providers::FetchError, /500/)
    end
  end

  describe '#fetch' do
    it 'sums up what arrived' do
      _, summary = VCR.use_cassette('energy_charts/price') { price_series.fetch }

      expect(summary).to match(/\A\d+ prices\z/)
    end

    it 'refuses an answer without prices' do
      stub_price_request(unit: 'EUR / MWh', data: [])

      expect { price_series.fetch }.to raise_error(Providers::FetchError, 'no prices in the answer')
    end
  end
end
