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
