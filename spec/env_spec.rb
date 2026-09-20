require 'env'

describe Env do
  describe '.[]' do
    it 'reads the value' do
      with_env(SOME_SETTING: 'value') { expect(described_class['SOME_SETTING']).to eq('value') }
    end

    it 'removes the spaces around the value' do
      with_env(SOME_SETTING: ' value ') { expect(described_class['SOME_SETTING']).to eq('value') }
    end

    it 'treats a blank value as unset' do
      with_env(SOME_SETTING: '  ') { expect(described_class['SOME_SETTING']).to be_nil }
    end

    it 'is nil for an unset key' do
      with_env(SOME_SETTING: nil) { expect(described_class['SOME_SETTING']).to be_nil }
    end
  end

  describe '.fetch' do
    it 'reads the value' do
      with_env(SOME_SETTING: 'value') { expect(described_class.fetch('SOME_SETTING')).to eq('value') }
    end

    it 'raises for a missing value' do
      with_env(SOME_SETTING: '') do
        expect { described_class.fetch('SOME_SETTING') }.to raise_error(Env::Error, 'SOME_SETTING is missing')
      end
    end
  end

  describe '.validate_presence!' do
    it 'accepts a value' do
      expect { described_class.validate_presence!('DE', 'COUNTRY') }.not_to raise_error
    end

    it 'rejects a blank value' do
      expect { described_class.validate_presence!(' ', 'COUNTRY') }.to raise_error(Env::Error, 'COUNTRY is missing')
    end
  end
end
