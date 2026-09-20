require 'user_agent'

describe UserAgent do
  describe '.current' do
    it 'names the app and links to the homepage' do
      with_env(COMMIT_VERSION: nil, VERSION: nil) do
        expect(described_class.current).to eq("#{described_class::APP_NAME} (+#{described_class::HOMEPAGE})")
      end
    end

    it 'carries the version when the build knows it' do
      with_env(COMMIT_VERSION: 'v1.2.3') do
        expect(described_class.current).to start_with("#{described_class::APP_NAME}/v1.2.3 ")
      end
    end
  end
end
