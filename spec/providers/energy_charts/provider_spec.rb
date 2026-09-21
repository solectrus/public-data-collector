require 'providers/energy_charts/provider'

# The interface every provider shares, seen through the one that reads two
# values.
describe Providers::EnergyCharts::Provider do
  subject(:provider) { described_class.from_env }

  def results
    VCR.use_cassettes([{ name: 'energy_charts/price' }, { name: 'energy_charts/share' }]) { provider.call.to_a }
  end

  describe '#call' do
    it 'yields one result per value' do
      expect(results.map(&:subject)).to eq(['day-ahead prices for DE-LU', 'renewable shares for DE'])
      expect(results).to all(be_ok)
      expect(results.map { |result| result.batch.measurement }.uniq).to eq(['my-measurement'])
      expect(results.map(&:summary)).to all(be_a(String))
    end

    it 'yields the reason of a value whose source failed, and keeps the others' do
      stub_request(:get, %r{api\.energy-charts\.info/v2/signal}).to_return(status: 500)

      price, share = results

      expect(price).to be_ok
      expect(share).not_to be_ok
      expect(share.batch).to be_nil
      expect(share.error).to start_with('500')
    end

    it 'yields the reason of an answer in an unexpected shape, and keeps the others' do
      stub_request(:get, %r{api\.energy-charts\.info/v2/signal}).to_return(status: 200, body: '[1, 2]')

      price, share = results

      expect(price).to be_ok
      expect(share).not_to be_ok
      expect(share.error).to start_with('unexpected answer (TypeError: ')
    end
  end

  describe '#descriptions' do
    it 'names each value, its source and its sensors' do
      expect(provider.descriptions).to eq(
        [
          'day-ahead prices for DE-LU from Energy-Charts => my-measurement:my-price',
          'renewable shares for DE from Energy-Charts => my-measurement:my-share'
        ],
      )
    end
  end

  describe 'the pace' do
    it 'reads on every cycle, no faster than the rate limit allows' do
      expect(provider.schedule).to eq(Providers::Schedule::EveryCycle.new(minimum_interval: 60))
    end
  end
end
