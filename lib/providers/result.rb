module Providers
  # What one series delivered in one read: its Batch and a few words on
  # what arrived, or the reason it failed.
  Result =
    Data.define(:subject, :batch, :summary, :error) do
      def initialize(subject:, batch: nil, summary: nil, error: nil) = super

      def ok? = error.nil?
    end
end
