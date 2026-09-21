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

      today = Date.today
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
