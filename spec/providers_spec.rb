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

    describe 'the switches' do
      it 'builds only the providers that are on' do
        with_env(ENABLE_GAS: 'false', ENABLE_PUBLIC_GRID: nil) do
          expect(from_env.map(&:class)).to eq([Providers::OilBulletin::Provider])
        end
      end

      it 'reads no settings of a provider that is off' do
        # Sweden has four bidding zones, so Energy-Charts would need BIDDING_ZONE
        with_env(COUNTRY: 'SE', ENABLE_PUBLIC_GRID: 'false') do
          expect(from_env.map(&:class)).to contain_exactly(
            Providers::Eurostat::Provider, Providers::OilBulletin::Provider,
          )
        end
      end

      it 'rejects a collector without a provider' do
        with_env(ENABLE_FUEL: nil, ENABLE_GAS: nil, ENABLE_PUBLIC_GRID: 'false') do
          expect { from_env }.to raise_error(
            Env::Error,
            'No source is enabled. Set at least one of ENABLE_PUBLIC_GRID, ENABLE_GAS, ENABLE_FUEL to true',
          )
        end
      end
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
