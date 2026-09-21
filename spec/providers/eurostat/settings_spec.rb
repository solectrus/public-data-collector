require 'providers/eurostat/settings'

describe Providers::Eurostat::Settings do
  let(:valid_options) { { country: 'DE', measurement: 'my-gas' } }

  describe 'validation' do
    it 'needs a country' do
      expect { described_class.new(**valid_options, country: '') }.to raise_error(Env::Error, /COUNTRY is missing/)
    end

    it 'needs a measurement' do
      expect { described_class.new(**valid_options, measurement: ' ') }
        .to raise_error(Env::Error, /GAS_MEASUREMENT is missing/)
    end
  end

  describe '.from_env' do
    it 'reads the settings' do
      expect(described_class.from_env).to have_attributes(country: 'DE', measurement: 'my-gas')
    end

    it 'falls back to the default measurement when the value is blank' do
      with_env(GAS_MEASUREMENT: '') { expect(described_class.from_env.measurement).to eq('Gas') }
    end
  end
end
