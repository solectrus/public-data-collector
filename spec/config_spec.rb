require 'config'

describe Config do
  let(:valid_options) do
    {
      interval: 900,
      influx_host: 'influx.example.com',
      influx_schema: 'https',
      influx_port: '443',
      influx_token: 'this.is.just.an.example',
      influx_org: 'my-org',
      influx_bucket: 'my-bucket',
    }
  end

  describe '#influx_url' do
    it 'joins schema, host and port' do
      expect(described_class.new(**valid_options).influx_url).to eq('https://influx.example.com:443')
    end
  end

  describe 'validation' do
    it 'needs every option' do
      expect { described_class.new }.to raise_error(ArgumentError)
    end

    it 'rejects an unusable URL' do
      expect { described_class.new(**valid_options, influx_schema: 'foo') }
        .to raise_error(Env::Error, /URL is invalid/)
    end
  end

  describe '.from_env' do
    it 'reads the settings' do
      expect(described_class.from_env).to have_attributes(
        interval: 60,
        influx_host: 'localhost',
        influx_schema: 'http',
        influx_port: '8086',
        influx_token: 'my-token',
        influx_org: 'my-org',
        influx_bucket: 'my-bucket',
      )
    end

    it 'falls back to the defaults when a value is blank' do
      with_env(INTERVAL: '', INFLUX_SCHEMA: ' ', INFLUX_PORT: '') do
        expect(described_class.from_env).to have_attributes(interval: 3600, influx_schema: 'http', influx_port: '8086')
      end
    end

    it 'needs the host' do
      with_env(INFLUX_HOST: '') do
        expect { described_class.from_env }.to raise_error(Env::Error, 'INFLUX_HOST is missing')
      end
    end
  end
end
