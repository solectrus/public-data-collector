module Providers
  # A fetch that delivered nothing to write. The message says why, and the
  # provider prints it in the line of that fetch. Nothing below the
  # provider prints a failure itself.
  #
  # `status` is the HTTP status of the answer, or nil when there was no
  # answer. A series can tell from it that a source has no data for a
  # request, which is not always an error.
  class FetchError < StandardError
    def initialize(message = nil, status: nil)
      super(message)
      @status = status
    end

    attr_reader :status
  end
end
