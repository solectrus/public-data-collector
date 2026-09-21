require 'providers/country'

describe Providers::Country do
  describe '.iso' do
    it 'upcases the code' do
      expect(described_class.iso('de')).to eq('DE')
    end

    it 'removes the spaces around the code' do
      expect(described_class.iso(' at ')).to eq('AT')
    end

    # The European Union writes Greece as EL, ISO 3166 writes it as GR
    it 'translates the EU code of Greece' do
      expect(described_class.iso('EL')).to eq('GR')
    end
  end

  describe '.eu' do
    it 'upcases the code' do
      expect(described_class.eu('de')).to eq('DE')
    end

    it 'translates the ISO code of Greece' do
      expect(described_class.eu('GR')).to eq('EL')
    end
  end
end
