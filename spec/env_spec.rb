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

  describe '.enabled?' do
    it 'is true for true' do
      with_env(SOME_SWITCH: 'true') { expect(described_class.enabled?('SOME_SWITCH')).to be(true) }
    end

    it 'ignores the case' do
      with_env(SOME_SWITCH: 'TRUE') { expect(described_class.enabled?('SOME_SWITCH')).to be(true) }
    end

    it 'is false for false' do
      with_env(SOME_SWITCH: 'false') { expect(described_class.enabled?('SOME_SWITCH')).to be(false) }
    end

    it 'is false for an unset key' do
      with_env(SOME_SWITCH: nil) { expect(described_class.enabled?('SOME_SWITCH')).to be(false) }
    end

    it 'raises for another value' do
      with_env(SOME_SWITCH: 'yes') do
        expect { described_class.enabled?('SOME_SWITCH') }
          .to raise_error(Env::Error, 'SOME_SWITCH is invalid: yes (true or false)')
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
