require 'extent'
require 'providers/energy_charts/co2_series'
require 'providers/energy_charts/settings'

describe Providers::EnergyCharts::Co2Series do
  subject(:co2_series) { described_class.new(Providers::EnergyCharts::Settings.from_env) }

  # A quarter hour with every required source: 14,040,000 MW g/kWh of
  # emissions over (50,000 - 2,000) MW * 0.947 of consumption
  let(:values) do
    {
      fossil_brown_coal_lignite: 10_000.0, fossil_hard_coal: 0.0, fossil_gas: 5000.0, fossil_oil: 0.0,
      waste: 0.0, others: 1000.0, fossil_coal_derived_gas: 0.0, biomass: 4000.0, solar: 20_000.0,
      wind_onshore: 10_000.0, wind_offshore: 0.0, hydro_run_of_river: 0.0,
      hydro_pumped_storage_consumption: -2000.0, load_incl_self_consumption: 55_000.0,
    }
  end

  # Without days, the stub answers every request
  def stub_total_power(data, first: nil, last: nil)
    stub = stub_request(:get, %r{api\.energy-charts\.info/v2/total_power})
    stub = stub.with(query: { country: 'de', start: first, end: last }) if first

    stub.to_return(status: 200, body: JSON.generate(unit: 'MW', data:))
  end

  def entry(time, values) = { timestamp: time.iso8601, values: }

  describe '#records' do
    context 'with a recorded answer of the API' do
      it 'returns a plausible intensity for every complete quarter hour' do
        intensities = VCR.use_cassette('energy_charts/co2') { co2_series.records }

        expect(intensities).not_to be_empty
        expect(intensities.map { |intensity| intensity.starts_at.localtime.min }.uniq).to contain_exactly(0, 15, 30, 45)
        expect(intensities.map(&:co2)).to all(be_between(50, 900))
      end
    end

    it 'divides the emissions by the consumption' do
      stub_total_power([entry(Time.local(2026, 10, 9, 12), values)])

      expect(co2_series.records.first).to have_attributes(starts_at: Time.local(2026, 10, 9, 12), co2: 309)
    end

    it 'counts nothing from a negative value' do
      stub_total_power([entry(Time.local(2026, 10, 9, 12), values.merge(solar: -5.0, nuclear: -1.0))])

      # The 20,000 MW of solar are gone: 14,040,000 / (28,000 * 0.947)
      expect(co2_series.records.first.co2).to eq(529)
    end

    it 'skips a quarter hour without every required source' do
      stub_total_power(
        [
          entry(Time.local(2026, 10, 9, 12), values),
          entry(Time.local(2026, 10, 9, 12, 15), values.merge(solar: nil)),
          entry(Time.local(2026, 10, 9, 12, 30), values.except(:wind_offshore))
        ],
      )

      expect(co2_series.records.map(&:starts_at)).to eq([Time.local(2026, 10, 9, 12)])
    end

    it 'keeps a quarter hour without coal-derived gas, which is part of the others in some years' do
      stub_total_power([entry(Time.local(2021, 6, 1, 12), values.except(:fossil_coal_derived_gas))])

      expect(co2_series.records.first.co2).to eq(309)
    end

    it 'keeps a quarter hour without the sources that are small or gone' do
      stub_total_power([entry(Time.local(2026, 10, 9, 12), values.except(:hydro_pumped_storage_consumption))])

      # 14,040,000 / (50,000 * 0.947)
      expect(co2_series.records.first.co2).to eq(297)
    end

    it 'skips a quarter hour without consumption' do
      zero = values.transform_values { 0.0 }
      stub_total_power([entry(Time.local(2026, 10, 9, 12), zero)])

      expect(co2_series.records).to be_empty
    end

    it 'skips an entry without values' do
      stub_total_power([{ timestamp: Time.local(2026, 10, 9, 12).iso8601, values: nil }])

      expect(co2_series.records).to be_empty
    end

    it 'asks for yesterday and today, because the last quarter hours arrive after midnight' do
      allow(Time).to receive(:now).and_return(Time.local(2026, 10, 10, 0, 30))
      stub = stub_total_power([], first: '2026-10-09', last: '2026-10-10')

      co2_series.records

      expect(stub).to have_been_requested
    end
  end

  describe 'the history' do
    before do
      allow(Time).to receive(:now).and_return(Time.local(2026, 10, 10, 12))
      stub_const('Providers::EnergyCharts::Client::SPACING', 0)
    end

    it 'reads the days before yesterday, then yesterday and today' do
      stub_total_power([entry(Time.local(2026, 9, 1), values)], first: '2026-09-01', last: '2026-10-08')
      stub_total_power([entry(Time.local(2026, 10, 9), values)], first: '2026-10-09', last: '2026-10-10')

      batch, summary = co2_series.fetch(Time.local(2026, 9, 1))

      expect(batch.rows).to eq(
        [
          Batch::Row.new(time: Time.local(2026, 9, 1), fields: { 'my-co2' => 309 }),
          Batch::Row.new(time: Time.local(2026, 10, 9), fields: { 'my-co2' => 309 })
        ],
      )
      expect(summary).to eq('2 values (from 2026-09-01)')
    end

    it 'reads only the day before yesterday after a restart' do
      stub_total_power([entry(Time.local(2026, 10, 8), values)], first: '2026-10-08', last: '2026-10-08')
      stub_total_power([entry(Time.local(2026, 10, 9), values)], first: '2026-10-09', last: '2026-10-10')
      stored = Extent.new(oldest: Time.local(2020, 1, 1), newest: Time.local(2026, 10, 9, 23))
      extents = { %w[my-measurement my-co2] => stored }

      batch, = co2_series.fetch(Time.local(2020, 1, 1), extents:)

      expect(batch.rows.map(&:time)).to eq([Time.local(2026, 10, 8), Time.local(2026, 10, 9)])
    end
  end

  describe '#fetch' do
    it 'refuses an answer without a complete quarter hour' do
      stub_total_power([])

      expect { co2_series.fetch }.to raise_error(Providers::FetchError, 'no CO2 intensities in the answer')
    end
  end
end
