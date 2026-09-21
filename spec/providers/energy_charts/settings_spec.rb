require 'providers/energy_charts/settings'

describe Providers::EnergyCharts::Settings do
  let(:valid_options) do
    {
      bzn: 'DE-LU',
      country: 'DE',
      measurement: 'my-measurement',
      field_price: 'amount',
      field_share: 'share',
    }
  end

  describe 'validation' do
    describe 'the day-ahead price' do
      it 'needs a bidding zone' do
        expect { described_class.new(**valid_options, bzn: ' ') }
          .to raise_error(Env::Error, /PUBLIC_GRID_BIDDING_ZONE is missing/)
      end

      it 'needs a measurement' do
        expect { described_class.new(**valid_options, measurement: '') }
          .to raise_error(Env::Error, /PUBLIC_GRID_MEASUREMENT is missing/)
      end

      it 'needs a field' do
        expect { described_class.new(**valid_options, field_price: '') }
          .to raise_error(Env::Error, /PUBLIC_GRID_FIELD_PRICE is missing/)
      end
    end

    describe 'the renewable share' do
      it 'needs a country' do
        expect { described_class.new(**valid_options, country: '') }
          .to raise_error(Env::Error, /COUNTRY is missing/)
      end

      it 'needs a field' do
        expect { described_class.new(**valid_options, field_share: '') }
          .to raise_error(Env::Error, /PUBLIC_GRID_FIELD_RENEWABLE_SHARE is missing/)
      end

      it 'rejects one field name for the price and the share' do
        expect { described_class.new(**valid_options, field_price: 'value', field_share: 'value') }
          .to raise_error(Env::Error, /they must differ/)
      end
    end
  end

  describe '.from_env' do
    it 'reads the settings' do
      expect(described_class.from_env).to have_attributes(
        bzn: 'DE-LU',
        country: 'DE',
        measurement: 'my-measurement',
        field_price: 'my-price',
        field_share: 'my-share',
      )
    end

    it 'upcases the country' do
      with_env(COUNTRY: 'at') { expect(described_class.from_env.country).to eq('AT') }
    end

    it 'falls back to the defaults when a value is blank' do
      blank = {
        PUBLIC_GRID_MEASUREMENT: '',
        PUBLIC_GRID_FIELD_PRICE: '',
        PUBLIC_GRID_FIELD_RENEWABLE_SHARE: ' ',
        PUBLIC_GRID_BIDDING_ZONE: '',
      }

      with_env(**blank) do
        expect(described_class.from_env).to have_attributes(
          measurement: 'PublicGrid',
          field_price: 'price',
          field_share: 'renewable_share',
          bzn: 'DE-LU',
        )
      end
    end
  end
end
