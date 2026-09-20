require 'app_version'

describe AppVersion do
  describe '.current' do
    it 'prefers COMMIT_VERSION' do
      with_env(COMMIT_VERSION: 'v0.10.1-3-g2d8f177', VERSION: 'develop') do
        expect(described_class.current).to eq('v0.10.1-3-g2d8f177')
      end
    end

    it 'falls back to VERSION when COMMIT_VERSION is blank' do
      with_env(COMMIT_VERSION: '', VERSION: 'develop') do
        expect(described_class.current).to eq('develop')
      end
    end

    it 'is nil when both are blank' do
      with_env(COMMIT_VERSION: '', VERSION: '') { expect(described_class.current).to be_nil }
    end

    it 'is nil when both are unset' do
      with_env(COMMIT_VERSION: nil, VERSION: nil) { expect(described_class.current).to be_nil }
    end
  end
end
