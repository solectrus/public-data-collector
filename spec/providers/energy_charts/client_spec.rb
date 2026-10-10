require 'providers/energy_charts/client'

describe Providers::EnergyCharts::Client do
  # Loop stubs its sleep in the same way
  let(:client) { described_class.new }

  before { allow(client).to receive(:sleep) }

  def stub_answer(status: 200)
    stub_request(:get, /api\.energy-charts\.info/).to_return(status:, body: '{}')
  end

  describe '#get' do
    it 'waits between two requests to the same endpoint' do
      stub_answer

      2.times { client.get('/v2/price') }

      expect(client).to have_received(:sleep).once.with(be_within(1).of(31))
    end

    it 'does not wait between two endpoints' do
      stub_answer

      client.get('/v2/price')
      client.get('/v2/signal')

      expect(client).not_to have_received(:sleep)
    end

    it 'does not wait when the last request is long ago' do
      stub_answer
      client.get('/v2/price')
      allow(Time).to receive(:now).and_return(Time.now + 60)

      client.get('/v2/price')

      expect(client).not_to have_received(:sleep)
    end

    # The rate limit counts a request that failed as well
    it 'waits after a request that failed' do
      stub_answer(status: 500)
      expect { client.get('/v2/price') }.to raise_error(Providers::FetchError)
      stub_answer

      client.get('/v2/price')

      expect(client).to have_received(:sleep).once
    end
  end
end
