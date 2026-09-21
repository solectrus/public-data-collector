require 'providers/schedule'

describe Providers::Schedule do
  let(:now) { Time.local(2026, 9, 21, 12) }

  describe Providers::Schedule::EveryCycle do
    subject(:schedule) { described_class.new(minimum_interval: 60) }

    it 'is due on every cycle' do
      expect(schedule.due?(now:, last_read: now)).to be(true)
    end

    it 'follows the interval' do
      expect(schedule.wake_after(900, now:)).to eq(900)
    end

    it 'accepts one second by default' do
      expect(described_class.new.minimum_interval).to eq(1)
    end

    it 'names the interval' do
      expect(schedule.description(900)).to eq('every 900 seconds')
    end
  end

  describe Providers::Schedule::Weekly do
    subject(:schedule) { described_class.new(5, 6) }

    let(:thursday) { Time.local(2026, 9, 17, 12) }
    let(:friday_slot) { Time.local(2026, 9, 18, 6) }

    it 'is due at its slot' do
      expect(schedule.due?(now: friday_slot, last_read: thursday)).to be(true)
    end

    it 'is not due on its weekday before its hour' do
      expect(schedule.due?(now: friday_slot - 60, last_read: thursday)).to be(false)
    end

    it 'is due once per slot' do
      expect(schedule.due?(now: friday_slot + 3600, last_read: friday_slot)).to be(false)
    end

    it 'is due after a missed slot' do
      expect(schedule.due?(now: friday_slot + (86_400 * 2), last_read: thursday)).to be(true)
    end

    it 'is not due on another day' do
      expect(schedule.due?(now: friday_slot + (86_400 * 3), last_read: friday_slot)).to be(false)
    end

    it 'wakes the loop at its next slot' do
      expect(schedule.wake_after(900, now: thursday)).to eq(18 * 3600)
      expect(schedule.wake_after(900, now: friday_slot)).to eq(7 * 86_400)
      expect(schedule.wake_after(900, now: friday_slot - 0.5)).to eq(1)
    end

    it 'accepts any interval' do
      expect(schedule.minimum_interval).to eq(0)
    end

    it 'names its weekday and hour' do
      expect(schedule.description(900)).to eq('on Friday at 06:00')
    end
  end
end
