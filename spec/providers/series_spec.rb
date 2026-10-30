require 'providers/series'

describe Providers::Series do
  subject(:series) { series_class.new(records) }

  let(:time) { Time.new(2026, 9, 14) }
  let(:record_class) { Data.define(:starts_at, :price, :volume) }

  # The smallest series: the records it is built with stand in for the
  # settings, and `records` hands them back.
  let(:series_class) do
    Class.new(described_class) do
      def label = 'prices'
      def subject = 'prices for DE'
      def measurement = 'my-measurement'
      def fields = { price: 'my-price', volume: 'my-volume' }
      def records = settings
      def nothing_found = 'no prices'
      def summary(records) = "#{records.size} prices"
    end
  end

  describe '#fetch' do
    context 'with records' do
      let(:records) { [record_class.new(time, 0.1, 5), record_class.new(time + 900, 0.2, nil)] }

      it 'names the batch and its measurement' do
        expect(series.fetch.first).to have_attributes(measurement: 'my-measurement')
      end

      it 'maps every record accessor to its field, one row per record' do
        expect(series.fetch.first.rows).to eq(
          [
            Batch::Row.new(time:, fields: { 'my-price' => 0.1, 'my-volume' => 5 }),
            Batch::Row.new(time: time + 900, fields: { 'my-price' => 0.2 })
          ],
        )
      end

      it 'sums up what arrived' do
        expect(series.fetch.last).to eq('2 prices')
      end
    end

    context 'with a record without a single value' do
      let(:records) { [record_class.new(time, nil, nil)] }

      it 'writes no row' do
        expect(series.fetch.first.rows).to be_empty
      end
    end

    context 'without records' do
      let(:records) { [] }

      it 'raises the reason' do
        expect { series.fetch }.to raise_error(Providers::FetchError, 'no prices')
      end
    end

    context 'with a time to start from' do
      let(:records) { (0..3).map { |week| record_class.new(time + (week * 7 * 86_400), 0.1 + week, nil) } }

      it 'keeps the records from then on, and the newest one before' do
        batch, = series.fetch(time + (15 * 86_400))

        expect(batch.rows.map(&:time)).to eq([time + (14 * 86_400), time + (21 * 86_400)])
      end

      it 'keeps every record when the time is before the first one' do
        batch, = series.fetch(time - 86_400)

        expect(batch.rows.size).to eq(4)
      end

      it 'keeps the newest record when the time is after the last one' do
        batch, = series.fetch(time + (100 * 86_400))

        expect(batch.rows.map(&:time)).to eq([time + (21 * 86_400)])
      end

      it 'sums up what it keeps, and from when' do
        expect(series.fetch(time + (15 * 86_400)).last).to eq('2 prices (from 2026-09-28)')
      end
    end
  end

  describe '#since' do
    let(:records) { [] }
    let(:history_start) { Time.new(2020, 11, 27) }

    before { allow(Time).to receive(:now).and_return(Time.new(2026, 9, 21)) }

    context 'without a window' do
      it 'writes everything' do
        expect(series.since(history_start, first_read: true)).to be_nil
      end
    end

    context 'with a window' do
      subject(:series) { Class.new(series_class) { def window = 10 }.new(records) }

      it 'writes the history at the first read' do
        expect(series.since(history_start, first_read: true)).to eq(history_start)
      end

      it 'writes the window at every later read' do
        expect(series.since(history_start, first_read: false)).to eq(Time.new(2026, 9, 11))
      end

      it 'never writes before the history, even within the window' do
        recent = Time.new(2026, 9, 20)

        expect(series.since(recent, first_read: false)).to eq(recent)
      end

      it 'writes everything without a start' do
        expect(series.since(nil, first_read: true)).to be_nil
      end
    end
  end

  describe '#targets' do
    let(:records) { [] }

    it 'names the measurement and every field' do
      expect(series.targets).to eq([%w[my-measurement my-price], %w[my-measurement my-volume]])
    end
  end
end
