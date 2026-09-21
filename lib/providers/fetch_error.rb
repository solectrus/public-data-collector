module Providers
  # A fetch that delivered nothing to write. The message says why, and the
  # provider prints it in the line of that fetch. Nothing below the
  # provider prints a failure itself.
  class FetchError < StandardError; end
end
