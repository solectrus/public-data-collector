require 'config'
require 'providers'

describe Providers do
  describe '.from_env' do
    def from_env(**)
      described_class.from_env(Config.from_env(**))
    end

    it 'builds every provider, from its folder' do
      expect(from_env.map(&:class)).to contain_exactly(
        Providers::EnergyCharts::Provider, Providers::Eurostat::Provider, Providers::OilBulletin::Provider,
      )
    end

    describe 'the interval' do
      it 'rejects an interval of zero' do
        expect { from_env(interval: 0) }.to raise_error(Env::Error, /Interval is invalid/)
      end

      it 'rejects an interval below the minimum of a provider' do
        expect { from_env(interval: 59) }.to raise_error(Env::Error, /minimum is 60/)
      end
    end
  end
end
