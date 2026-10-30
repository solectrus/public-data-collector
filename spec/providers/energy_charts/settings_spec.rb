require 'providers/energy_charts/settings'

describe Providers::EnergyCharts::Settings do
  describe 'validation' do
    it 'needs a country' do
      expect { described_class.new(country: '', bzn: 'DE-LU') }.to raise_error(Env::Error, /COUNTRY is missing/)
    end

    it 'needs a bidding zone' do
      expect { described_class.new(country: 'SE', bzn: nil) }.to raise_error(
        Env::Error,
        'BIDDING_ZONE is missing, because COUNTRY SE has no single bidding zone',
      )
    end
  end

  describe '.from_env' do
    it 'finds the bidding zone of the country' do
      expect(described_class.from_env).to have_attributes(country: 'DE', bzn: 'DE-LU')
    end

    it 'upcases the country' do
      with_env(COUNTRY: 'at') { expect(described_class.from_env).to have_attributes(country: 'AT', bzn: 'AT') }
    end

    it 'reads the bidding zone of a country with more than one zone' do
      with_env(COUNTRY: 'SE', BIDDING_ZONE: 'SE3') { expect(described_class.from_env.bzn).to eq('SE3') }
    end

    it 'finds the bidding zone when the value is blank' do
      with_env(BIDDING_ZONE: ' ') { expect(described_class.from_env.bzn).to eq('DE-LU') }
    end
  end

  describe Providers::EnergyCharts::BiddingZone do
    it 'knows the zone that Germany shares with Luxembourg' do
      expect([described_class.of('DE'), described_class.of('LU')]).to eq(%w[DE-LU DE-LU])
    end

    it 'knows the zone of a country with a zone of its own' do
      expect(described_class.of('fr')).to eq('FR')
    end

    it 'knows Greece by both codes' do
      expect([described_class.of('GR'), described_class.of('EL')]).to eq(%w[GR GR])
    end

    it 'knows the zone of Ireland' do
      expect(described_class.of('IE')).to eq('IE(SEM)')
    end

    it 'has no zone for a country with more than one zone' do
      expect(%w[DK IT NO SE].map { described_class.of(it) }).to all(be_nil)
    end
  end
end
