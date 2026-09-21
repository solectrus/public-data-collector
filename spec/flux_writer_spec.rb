require 'batch'
require 'config'
require 'flux_writer'

describe FluxWriter do
  subject(:flux_writer) { described_class.new(config: Config.from_env) }

  let(:time) { Time.new(2026, 9, 19, 12, 15, 0, '+02:00') }

  def batch(*rows)
    Batch.new(measurement: 'my-measurement', rows:)
  end

  describe '#points' do
    it 'writes one point per row into the measurement of the batch' do
      points = flux_writer.points(batch(Batch::Row.new(time:, fields: { 'price' => 0.1 })))

      expect(points.map(&:to_line_protocol)).to eq(["my-measurement price=0.1 #{time.to_i}"])
    end

    it 'writes every field of a row into one point' do
      row = Batch::Row.new(time:, fields: { 'price_petrol' => 2.357, 'price_diesel' => 2.426 })

      point = flux_writer.points(batch(row)).first

      expect(point.to_line_protocol).to eq("my-measurement price_diesel=2.426,price_petrol=2.357 #{time.to_i}")
    end
  end

  describe '#push' do
    it 'writes the points to InfluxDB' do
      stub = stub_request(:post, %r{/api/v2/write}).to_return(status: 204)

      flux_writer.push(batch(Batch::Row.new(time:, fields: { 'price' => 0.1 })))

      expect(stub).to have_been_requested
    end

    it 'writes nothing without rows' do
      stub = stub_request(:post, %r{/api/v2/write}).to_return(status: 204)

      flux_writer.push(batch)

      expect(stub).not_to have_been_requested
    end
  end

  describe '#ready?' do
    it 'is true when InfluxDB answers the ping' do
      stub_request(:get, %r{/ping}).to_return(status: 204, headers: { 'X-Influxdb-Version' => '2.7' })

      expect(flux_writer).to be_ready
    end

    it 'is false when InfluxDB does not' do
      stub_request(:get, %r{/ping}).to_return(status: 500)

      expect(flux_writer).not_to be_ready
    end
  end
end
