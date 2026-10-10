require 'config'
require 'flux_reader'

describe FluxReader do
  subject(:flux_reader) { described_class.new(config: Config.from_env) }

  # The annotated CSV that InfluxDB answers a query with
  def answer(*times)
    rows = times.map { |time| ",,0,#{time}" }

    [
      '#datatype,string,long,dateTime:RFC3339',
      '#group,false,false,false',
      '#default,_result,,',
      ',result,table,_time',
      *rows,
      ''
    ].join("\r\n")
  end

  def stub_query(body, status: 200)
    stub_request(:post, %r{/api/v2/query}).to_return(status:, body:, headers: { 'Content-Type' => 'text/csv' })
  end

  describe '#history_start' do
    let(:now) { Time.new(2026, 9, 21, 12) }

    def history_start
      result = nil
      stdout, = capture_output { result = flux_reader.history_start(except: [], now:) }

      [result, stdout]
    end

    it 'starts where the other data begins, and says so' do
      stub_query(answer('2020-11-27T17:35:48Z'))

      start, stdout = history_start

      expect(start).to eq(Time.utc(2020, 11, 27, 17, 35, 48))
      expect(stdout).to start_with('The other data in the bucket begins on Fri 2020-11-27 at ')
    end

    # A forecast is the only data of a new bucket, and it lies ahead
    it 'starts now when the other data begins in the future' do
      stub_query(answer('2026-09-22T06:00:00Z'))

      expect(history_start.first).to eq(now)
    end

    it 'starts now without other data' do
      stub_query('')

      start, stdout = history_start

      expect(start).to eq(now)
      expect(stdout).to eq("The bucket holds no other data, so no history is written.\n\n")
    end

    it 'starts now when InfluxDB refuses the query' do
      stub_query('{"code":"unauthorized","message":"unauthorized access"}', status: 401)

      start, stdout = history_start

      expect(start).to eq(now)
      expect(stdout).to start_with('Cannot find where the data in the bucket begins (unauthorized access)')
    end
  end

  describe '#extents' do
    let(:targets) { [%w[PublicGrid price], %w[PublicGrid renewable_share]] }
    let(:before) { Time.utc(2026, 10, 10) }

    # One point per field, as `first()` and `last()` answer
    def points(*rows)
      lines = rows.map { |measurement, field, time| ",,0,#{measurement},#{field},#{time}" }

      [
        '#datatype,string,long,string,string,dateTime:RFC3339',
        '#group,false,false,true,true,false',
        '#default,_result,,,,',
        ',result,table,_measurement,_field,_time',
        *lines,
        ''
      ].join("\r\n")
    end

    def stub_selector(selector, body)
      stub_query(body).with { |request| JSON.parse(request.body)['query'].include?("|> #{selector}") }
    end

    it 'answers the oldest point and the newest point before today of every field' do
      stub_selector('first()', points(%w[PublicGrid price 2020-11-27T17:00:00Z]))
      stub_selector('last()', points(%w[PublicGrid price 2026-10-09T21:00:00Z]))

      expect(flux_reader.extents(targets, before:)).to eq(
        %w[PublicGrid price] => Extent.new(
          oldest: Time.utc(2020, 11, 27, 17), newest: Time.utc(2026, 10, 9, 21),
        ),
      )
    end

    it 'answers no newest point for a field with points from today on alone' do
      stub_selector('first()', points(%w[PublicGrid price 2026-10-10T08:00:00Z]))
      stub_selector('last()', points)

      expect(flux_reader.extents(targets, before:).values).to eq(
        [Extent.new(oldest: Time.utc(2026, 10, 10, 8), newest: nil)],
      )
    end

    it 'asks for every field, and for the newest point before today' do
      stub = stub_query(points).with do |request|
        query = JSON.parse(request.body)['query']
        query.include?('(r._measurement == "PublicGrid" and r._field == "price") or ' \
                       '(r._measurement == "PublicGrid" and r._field == "renewable_share")') &&
          (query.include?('|> first()') || query.include?('stop: 2026-10-10T00:00:00Z'))
      end

      flux_reader.extents(targets, before:)

      expect(stub).to have_been_requested.twice
    end

    it 'asks nothing without fields' do
      expect(flux_reader.extents([], before:)).to eq({})
    end

    it 'answers nothing when InfluxDB refuses the query' do
      stub_query('{"code":"unauthorized","message":"unauthorized access"}', status: 401)

      expect(flux_reader.extents(targets, before:)).to eq({})
    end
  end

  describe '#oldest_time' do
    it 'answers the time of the oldest point' do
      stub_query(answer('2020-11-27T17:35:48Z'))

      expect(flux_reader.oldest_time(except: [])).to eq(Time.utc(2020, 11, 27, 17, 35, 48))
    end

    it 'answers nil for a bucket without other data' do
      stub_query('')

      expect(flux_reader.oldest_time(except: ['Fuel'])).to be_nil
    end

    it 'leaves out the given measurements, one comparison each' do
      stub = stub_query('').with do |request|
        JSON.parse(request.body)['query'].include?(
          '|> filter(fn: (r) => r._measurement != "Fuel" and r._measurement != "Gas")',
        )
      end

      flux_reader.oldest_time(except: %w[Fuel Gas])

      expect(stub).to have_been_requested
    end

    it 'reads every measurement when there is none to leave out' do
      stub = stub_query('').with { |request| !JSON.parse(request.body)['query'].include?('filter') }

      flux_reader.oldest_time(except: [])

      expect(stub).to have_been_requested
    end

    it 'keeps a quote in a measurement name inside the literal' do
      stub = stub_query('').with do |request|
        JSON.parse(request.body)['query'].include?('r._measurement != "my\\"fuel\\\\"')
      end

      flux_reader.oldest_time(except: ['my"fuel\\'])

      expect(stub).to have_been_requested
    end

    it 'raises when InfluxDB refuses the query' do
      stub_query('{"code":"unauthorized","message":"unauthorized access"}', status: 401)

      expect { flux_reader.oldest_time(except: []) }.to raise_error(InfluxDB2::InfluxError, /unauthorized/)
    end
  end
end
