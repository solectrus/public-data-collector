require 'providers/energy_charts/provider'

# The interface every provider shares, seen through the one that reads
# several values.
describe Providers::EnergyCharts::Provider do
  subject(:provider) { described_class.from_env }

  # One read alone. A second read within a few seconds waits for the rate
  # limit of the API.
  let(:results) do
    VCR.use_cassettes(%w[energy_charts/price energy_charts/share energy_charts/co2].map { { name: it } }) do
      provider.call.to_a
    end
  end

  describe '#call' do
    it 'yields one result per value' do
      expect(results.map(&:subject)).to eq(
        ['day-ahead prices for DE-LU', 'renewable shares for DE', 'CO2 intensities for DE'],
      )
      expect(results).to all(be_ok)
      expect(results.map { |result| result.batch.measurement }.uniq).to eq(['my-measurement'])
      expect(results.map(&:summary)).to all(be_a(String))
    end

    it 'yields the reason of a value whose source failed, and keeps the others' do
      stub_request(:get, %r{api\.energy-charts\.info/v2/signal}).to_return(status: 500)

      price, share, = results

      expect(price).to be_ok
      expect(share).not_to be_ok
      expect(share.batch).to be_nil
      expect(share.error).to start_with('500')
    end

    it 'yields the reason of an answer in an unexpected shape, and keeps the others' do
      stub_request(:get, %r{api\.energy-charts\.info/v2/signal}).to_return(status: 200, body: '[1, 2]')

      price, share, = results

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
          'renewable shares for DE from Energy-Charts => my-measurement:my-share',
          'CO2 intensities for DE from Energy-Charts => my-measurement:my-co2'
        ],
      )
    end

    # The emission factors describe the power plants of Germany
    it 'leaves out the CO2 intensity outside Germany' do
      with_env(COUNTRY: 'AT') do
        expect(described_class.from_env.descriptions).to eq(
          [
            'day-ahead prices for DE-LU from Energy-Charts => my-measurement:my-price',
            'renewable shares for AT from Energy-Charts => my-measurement:my-share'
          ],
        )
      end
    end
  end

  describe 'the pace' do
    it 'reads on every cycle, no faster than the rate limit allows' do
      expect(provider.schedule).to eq(Providers::Schedule::EveryCycle.new(minimum_interval: 60))
    end
  end
end
