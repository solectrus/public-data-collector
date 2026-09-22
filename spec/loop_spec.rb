require 'config'
require 'loop'

describe Loop do
  include XlsxBuilder

  let(:config) { Config.from_env }

  # The weekly sources read on Friday at 06:00
  let(:friday_early) { Time.local(2026, 9, 18, 5, 59) }
  let(:monday) { Time.local(2026, 9, 21, 12) }

  def stub_influx_ready(oldest: nil)
    stub_request(:get, %r{/ping}).to_return(status: 204, headers: { 'X-Influxdb-Version' => '2.7' })
    stub_influx_query(oldest)
  end

  # The answer to the question where the other data in the bucket begins,
  # as InfluxDB sends it. Without a time, the bucket holds no other data.
  def stub_influx_query(oldest)
    body = oldest ? "#datatype,string,long,dateTime:RFC3339\r\n,result,table,_time\r\n,,0,#{oldest}\r\n" : ''
    stub_request(:post, %r{/api/v2/query}).to_return(status: 200, body:, headers: { 'Content-Type' => 'text/csv' })
  end

  def stub_influx_write(status: 204)
    stub_request(:post, %r{/api/v2/write}).to_return(status:)
  end

  # The oil bulletin is a 4 MB spreadsheet, which has no place in a
  # cassette. Its download is stubbed, everything else is replayed.
  def stub_bulletin
    stub_request(:get, %r{energy\.ec\.europa\.eu/document/download}).to_return(status: 200, body: bulletin_file)
  end

  def bulletin_file
    header = ['Date', *%w[euro95 diesel heating_oil LPG].map { |p| "DE_price_with_tax_#{p}" }]
    rows = [header, [''], ['Date'], [46_279, 2357.0, 2426.0, 1683.0, 1086.5]]

    build_xlsx(rows)
  end

  def with_sources(&)
    stub_bulletin
    VCR.use_cassettes(
      %w[energy_charts/price energy_charts/share eurostat/gas_prices oil_bulletin/page].map { { name: it } },
      &
    )
  end

  # The loop takes any set of providers. Without Energy-Charts, it shows
  # how the loop runs when every provider reads weekly.
  def weekly_providers
    [Providers::Eurostat::Provider.from_env, Providers::OilBulletin::Provider.from_env]
  end

  # Runs the cycles on a fake clock that starts at `from`. A sleep moves
  # the clock on instead of waiting, so a spec of several cycles runs at
  # once and the loop wakes when its schedules say.
  def run_cycles(count, from:, **)
    now = from
    allow(Time).to receive(:now) { now }

    collector = described_class.new(config:, **)
    allow(collector).to receive(:sleep) { |seconds| now += seconds }
    collector.start(max_count: count)
  end

  describe '.start' do
    it 'fetches every source and writes it' do
      stub_influx_ready
      write_stub = stub_influx_write

      stdout, stderr = capture_output { with_sources { described_class.start(config:, max_count: 1) } }

      expect(stdout).to match(/^Cycle #1 at \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}$/)
      expect(stdout).to include("  Energy-Charts\n    ✓ day-ahead prices for DE-LU: ")
      expect(stdout).to include('    ✓ renewable shares for DE: ')
      expect(stdout).to include("  EU Weekly Oil Bulletin\n    ✓ fuel prices for DE: ")
      expect(stdout).to include("  Eurostat\n    ✓ gas prices for DE: ")
      expect(stderr).to be_empty

      # One write per source
      expect(write_stub).to have_been_requested.times(4)
    end

    describe 'the two paces' do
      it 'reads Energy-Charts on every cycle and the weekly sources once' do
        stub_influx_ready
        write_stub = stub_influx_write

        capture_output { with_sources { run_cycles(3, from: monday) } }

        # Price and share three times, fuel and gas on the first cycle alone
        expect(write_stub).to have_been_requested.times((3 * 2) + 2)
      end

      # The interval is 60 seconds, so the cycles run at 05:59, 06:00 and 06:01
      it 'reads the weekly sources at the start and once at their hour' do
        stub_influx_ready
        write_stub = stub_influx_write

        capture_output { with_sources { run_cycles(3, from: friday_early) } }

        expect(write_stub).to have_been_requested.times((3 * 2) + (2 * 2))
      end

      it 'sleeps until the next Friday without Energy-Charts' do
        stub_influx_ready
        write_stub = stub_influx_write

        stdout, = capture_output { with_sources { run_cycles(2, from: monday, providers: weekly_providers) } }

        expect(stdout).to include('Next cycle on Fri 2026-09-25 at 06:00:00')

        # The first cycle always reads, the second one because it is Friday
        expect(write_stub).to have_been_requested.times(2 * 2)
      end

      # The loop never wakes before a slot, but a clock that stands still
      # shows what happens then
      it 'says it has nothing to do when no source is due' do
        stub_influx_ready
        write_stub = stub_influx_write
        allow(Time).to receive(:now).and_return(monday)
        collector = described_class.new(config:, providers: weekly_providers)
        allow(collector).to receive(:sleep)

        stdout, = capture_output { with_sources { collector.start(max_count: 2) } }

        expect(stdout).to include('Nothing to do, no source is due.')

        # The first cycle reads, so that a new container does not wait for Friday
        expect(write_stub).to have_been_requested.twice
      end
    end

    describe 'the history' do
      # A bulletin of 40 weeks, the newest on 2026-09-14, the oldest on 2025-12-15
      def long_bulletin
        header = ['Date', *%w[euro95 diesel heating_oil LPG].map { |p| "DE_price_with_tax_#{p}" }]
        weeks = (0...40).map { |i| [46_279 - (i * 7), 2000.0 + i, 2100.0 + i, nil, nil] }

        build_xlsx([header, [''], ['Date'], *weeks])
      end

      def oil_bulletin_bodies(oldest:)
        stub_influx_ready(oldest:)
        stub_request(:get, %r{energy\.ec\.europa\.eu/document/download}).to_return(status: 200, body: long_bulletin)
        bodies = []
        stub_request(:post, %r{/api/v2/write}).to_return do |request|
          bodies << request.body
          { status: 204 }
        end

        stdout, = capture_output do
          VCR.use_cassette('oil_bulletin/page') do
            run_cycles(2, from: friday_early, providers: [Providers::OilBulletin::Provider.from_env])
          end
        end

        [stdout, bodies]
      end

      it 'starts where the other data in the bucket begins, without its own measurements' do
        stub_influx_ready
        stub_influx_write

        stdout, = capture_output { with_sources { run_cycles(1, from: monday) } }

        expect(stdout).to match(/^The bucket holds no other data, so no history is written\.$/)
        expect(
          a_request(:post, %r{/api/v2/query}).with do |request|
            JSON.parse(request.body)['query'].include?(
              'r._measurement != "my-measurement" and r._measurement != "my-gas" and r._measurement != "my-fuel"',
            )
          end,
        ).to have_been_made
      end

      it 'writes the history at the first read, and eight weeks at every later read' do
        stdout, bodies = oil_bulletin_bodies(oldest: '2026-03-02T12:00:00Z')

        expect(stdout).to include('The other data in the bucket begins on Mon 2026-03-02 at ')

        # First read: the 28 weeks from 2026-03-09 on, and the one before.
        # Friday: the 8 weeks from 2026-07-27 on, and the one before.
        expect(bodies.map { |body| body.lines.size }).to eq([29, 9])
      end

      it 'writes the newest week alone when the bucket holds no other data' do
        _, bodies = oil_bulletin_bodies(oldest: nil)

        expect(bodies.map { |body| body.lines.size }).to eq([1, 1])
      end

      it 'writes no history when the token may not read' do
        stub_request(:get, %r{/ping}).to_return(status: 204, headers: { 'X-Influxdb-Version' => '2.7' })
        stub_request(:post, %r{/api/v2/query})
          .to_return(status: 401, body: '{"code":"unauthorized","message":"unauthorized access"}')
        stub_influx_write

        stdout, = capture_output { with_sources { run_cycles(1, from: monday) } }

        expect(stdout).to include(
          'Cannot find where the data in the bucket begins (unauthorized access), so no history is written. ' \
          'The token needs read permission for that.',
        )
        expect(stdout).to include('✓ fuel prices for DE: 1 weeks')
      end
    end

    context 'when InfluxDB is not ready yet' do
      it 'waits until it answers' do
        stub_request(:get, %r{/ping}).to_return({ status: 500 }, { status: 500 }, { status: 204 })
        stub_influx_query(nil)
        stub_influx_write

        stub_const('FluxWriter::READY_RETRY_WAIT', 0)

        stdout, = capture_output do
          with_sources { described_class.start(config:, max_count: 1, max_wait: 5) }
        end

        expect(stdout).to include('Wait until InfluxDB is ready ..... OK')
      end

      it 'gives up when it stays silent' do
        stub_request(:get, %r{/ping}).to_return(status: 500)

        stub_const('FluxWriter::READY_RETRY_WAIT', 0)

        stdout, = capture_output do
          expect { described_class.start(config:, max_wait: 2) }.to raise_error(Loop::NotReady)
        end

        expect(stdout).to include('InfluxDB not ready after 0 seconds - aborting')
      end

      it 'names the reason' do
        stub_request(:get, %r{/ping}).to_raise(SocketError.new('getaddrinfo: Name does not resolve'))

        stub_const('FluxWriter::READY_RETRY_WAIT', 0)

        stdout, = capture_output do
          expect { described_class.start(config:, max_wait: 0) }.to raise_error(Loop::NotReady)
        end

        expect(stdout).to include('InfluxDB not ready after 0 seconds (getaddrinfo: Name does not resolve) - aborting')
      end
    end

    # One source that fails must not stop the others
    it 'keeps the other sources when the oil bulletin fails' do
      stub_influx_ready
      stub_request(:get, /energy\.ec\.europa\.eu/).to_return(status: 500)
      write_stub = stub_influx_write

      stdout, stderr = capture_output do
        VCR.use_cassettes(
          [{ name: 'energy_charts/price' }, { name: 'energy_charts/share' }, { name: 'eurostat/gas_prices' }],
        ) { described_class.start(config:, max_count: 1) }
      end

      expect(stdout).to include('    ✗ fuel prices for DE: 500')
      expect(stdout).to include('    ✓ gas prices for DE: ')
      expect(write_stub).to have_been_requested.times(3)
      expect(stderr).to be_empty
    end

    it 'keeps the other sources when Energy-Charts fails' do
      stub_influx_ready
      stub_request(:get, /api\.energy-charts\.info/).to_return(status: 500)
      write_stub = stub_influx_write

      stdout, = capture_output do
        stub_bulletin
        VCR.use_cassettes([{ name: 'eurostat/gas_prices' }, { name: 'oil_bulletin/page' }]) do
          described_class.start(config:, max_count: 1)
        end
      end

      expect(stdout).to include('    ✗ day-ahead prices for DE-LU: 500')
      expect(stdout).to include('    ✓ fuel prices for DE: ')
      expect(write_stub).to have_been_requested.twice
    end

    # A weekly source would otherwise wait a week for the next read
    it 'tries a failed source again after one interval, whatever its schedule says' do
      stub_influx_ready
      write_stub = stub_influx_write
      stub_request(:get, %r{energy\.ec\.europa\.eu/document/download})
        .to_return({ status: 500 }, { status: 200, body: bulletin_file })

      stdout, = capture_output do
        VCR.use_cassettes([{ name: 'eurostat/gas_prices' }, { name: 'oil_bulletin/page' }]) do
          run_cycles(3, from: monday, providers: weekly_providers)
        end
      end

      cycles = stdout.split(/^Cycle #\d+/).drop(1)
      expect(cycles[0]).to include('✗ fuel prices for DE: 500', '✓ gas prices')
      expect(cycles[0]).to match(/Next attempt .*at 12:01:00/)
      expect(cycles[0]).to match(/Next cycle .*at 12:01:00/)
      expect(cycles[1]).to include('✓ fuel prices for DE')
      expect(cycles[1]).not_to include('gas prices')
      expect(cycles[1]).to include('Next cycle on Fri 2026-09-25 at 06:00:00')

      # Gas in the first cycle, fuel in the second, both on Friday
      expect(write_stub).to have_been_requested.times(4)
    end

    # A source that does not know the country fails for good
    it 'doubles the wait after every failure' do
      stub_influx_ready
      stub_influx_write
      download = stub_request(:get, %r{energy\.ec\.europa\.eu/document/download}).to_return(status: 500)

      stdout, = capture_output do
        VCR.use_cassette('oil_bulletin/page', allow_playback_repeats: true) do
          run_cycles(4, from: monday, providers: [Providers::OilBulletin::Provider.from_env])
        end
      end

      expect(stdout.scan(/Next cycle .*at (\S+)$/).flatten).to eq(%w[12:01:00 12:03:00 12:07:00])
      expect(download).to have_been_requested.times(4)
    end

    # With an interval of four days, the retry would come on Friday at noon
    it 'reads a failed weekly source at its slot, even before its retry' do
      stub_influx_ready
      stub_influx_write
      download = stub_request(:get, %r{energy\.ec\.europa\.eu/document/download}).to_return(status: 500)

      stdout, = capture_output do
        with_env(INTERVAL: (4 * 86_400).to_s) do
          VCR.use_cassette('oil_bulletin/page', allow_playback_repeats: true) do
            run_cycles(2, from: monday, providers: [Providers::OilBulletin::Provider.from_env])
          end
        end
      end

      expect(stdout).to include('Next attempt on Fri 2026-09-25 at 06:00:00')
      expect(stdout).to match(/^Cycle #2 at 2026-09-25 06:00:00/)
      expect(download).to have_been_requested.twice
    end

    it 'tries a source again whose write failed' do
      stub_influx_ready
      write_stub = stub_request(:post, %r{/api/v2/write}).to_return({ status: 500 }, { status: 204 })
      stub_const('Loop::PUSH_ATTEMPTS', 1)

      capture_output do
        VCR.use_cassettes([{ name: 'eurostat/gas_prices' }]) do
          run_cycles(2, from: monday, providers: [Providers::Eurostat::Provider.from_env])
        end
      end

      expect(write_stub).to have_been_requested.twice
    end

    it 'retries a failed write and gives up in the end' do
      stub_influx_ready
      write_stub = stub_influx_write(status: 500)

      # The waiting is removed, so the spec walks through the retry fast
      stub_const('Loop::PUSH_ATTEMPTS', 2)
      stub_const('Loop::PUSH_RETRY_WAIT', 0)

      stdout, = capture_output { with_sources { described_class.start(config:, max_count: 1) } }

      expect(stdout.scan('    ! InfluxDB: ').size).to eq(4)
      expect(stdout.scan(/^    ✗ .*, but not stored in InfluxDB \(.*, 2 attempts\)/).size).to eq(4)

      # Two attempts per source
      expect(write_stub).to have_been_requested.times(8)
    end
  end
end
