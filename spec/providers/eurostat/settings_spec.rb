require 'providers/eurostat/settings'

describe Providers::Eurostat::Settings do
  describe 'validation' do
    it 'needs a country' do
      expect { described_class.new(country: '') }.to raise_error(Env::Error, /COUNTRY is missing/)
    end
  end

  describe '.from_env' do
    it 'reads the country' do
      expect(described_class.from_env).to have_attributes(country: 'DE')
    end
  end
end
