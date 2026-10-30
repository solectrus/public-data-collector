require 'providers/energy_charts/settings'
require 'providers/energy_charts/share_series'

describe Providers::EnergyCharts::ShareSeries do
  subject(:share_series) { described_class.new(Providers::EnergyCharts::Settings.from_env) }

  def stub_share_request(data)
    stub_request(:get, /api\.energy-charts\.info/).to_return(
      status: 200,
      body: JSON.generate({ data: }),
      headers: { 'Content-Type' => 'application/json' },
    )
  end

  describe '#records' do
    context 'with a recorded answer of the API' do
      it 'returns a share for every quarter hour' do
        shares = VCR.use_cassette('energy_charts/share') { share_series.records }

        expect(shares).not_to be_empty
        expect(shares.map { |share| share.starts_at.localtime.min }.uniq).to contain_exactly(0, 15, 30, 45)
        expect(shares.map(&:share)).to all(be_a(Float).and(be >= 0))
      end
    end

    it 'reads the share as a float' do
      stub_share_request([{ timestamp: '2026-09-19T00:00:00+02:00', values: { share: 75.7 } }])

      shares = share_series.records

      expect(shares.size).to eq(1)
      expect(shares.first).to have_attributes(
        share: 75.7,
        starts_at: Time.new(2026, 9, 19, 0, 0, 0, '+02:00'),
      )
    end

    # The share is the renewable generation divided by the load, so it goes
    # above 100 percent when the country exports the surplus.
    it 'keeps a share above 100 percent' do
      stub_share_request([{ timestamp: '2026-09-19T14:00:00+02:00', values: { share: 132.8 } }])

      shares = share_series.records

      expect(shares.first.share).to eq(132.8)
    end

    it 'ignores the traffic signal that the same answer carries' do
      stub_share_request([{ timestamp: '2026-09-19T00:00:00+02:00', values: { share: 75.7, signal: 2 } }])

      shares = share_series.records

      expect(shares.size).to eq(1)
      expect(shares.first).not_to respond_to(:signal)
    end

    it 'skips an interval without a share' do
      stub_share_request(
        [
          { timestamp: '2026-09-19T00:00:00+02:00', values: { share: nil } },
          { timestamp: '2026-09-19T00:15:00+02:00', values: { share: 80.0 } }
        ],
      )

      shares = share_series.records

      expect(shares.size).to eq(1)
      expect(shares.first.starts_at).to eq(Time.new(2026, 9, 19, 0, 15, 0, '+02:00'))
    end

    it 'asks for the country' do
      stub_share_request([])

      share_series.records

      expect(
        a_request(:get, 'https://api.energy-charts.info/v2/signal').with(query: { country: 'de' }),
      ).to have_been_made
    end

    describe 'error handling' do
      it 'reports a server error' do
        stub_request(:get, /api\.energy-charts\.info/).to_return(status: 500)

        expect { share_series.records }.to raise_error(Providers::FetchError, /500/)
      end
    end
  end

  describe 'the history' do
    before do
      allow(Time).to receive(:now).and_return(Time.local(2026, 10, 10, 12))
      stub_const('Providers::EnergyCharts::Client::SPACING', 0)
      stub_share_request([{ timestamp: Time.local(2026, 10, 10).iso8601, values: { share: 110.8, signal: 2 } }])
    end

    # The answer of public_power: the share beside every kind of generation
    def stub_public_power(first, last, status: 200)
      values = { solar: 1234.5, load: 50_000.0, renewable_share_of_load: 75.7, renewable_share_of_generation: 70.1 }
      data = [{ timestamp: Date.parse(first).to_time.iso8601, values: }]

      stub_request(:get, 'https://api.energy-charts.info/v2/public_power')
        .with(query: { country: 'de', start: first, end: last })
        .to_return(status:, body: JSON.generate(unit: 'MW', data:))
    end

    it 'reads the days before today from public_power, and today from signal' do
      stub_public_power('2026-09-01', '2026-10-09')

      batch, = share_series.fetch(Time.local(2026, 9, 1))

      expect(batch.rows).to eq(
        [
          Batch::Row.new(time: Time.local(2026, 9, 1), fields: { 'renewable_share' => 75.7 }),
          Batch::Row.new(time: Time.local(2026, 10, 10), fields: { 'renewable_share' => 110.8 })
        ],
      )
    end

    # public_power answers 400 for a time before its data begins
    it 'ends the history at an older year that has no data' do
      stub_public_power('2025-10-10', '2026-10-09')
      stub_public_power('2024-10-10', '2025-10-09', status: 400)

      batch, = share_series.fetch(Time.local(2010, 1, 1))

      expect(batch.rows.map(&:time)).to eq([Time.local(2025, 10, 10), Time.local(2026, 10, 10)])
    end
  end

  describe '#fetch' do
    it 'sums up what arrived' do
      _, summary = VCR.use_cassette('energy_charts/share') { share_series.fetch }

      expect(summary).to match(/\A\d+ shares\z/)
    end

    it 'refuses an answer without shares' do
      stub_share_request([])

      expect { share_series.fetch }.to raise_error(Providers::FetchError, 'no shares in the answer')
    end
  end
end
