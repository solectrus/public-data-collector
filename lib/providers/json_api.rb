require 'json'

require 'providers/http'

module Providers
  # Base class of the clients that read a JSON API.
  #
  # This class makes the request and parses the answer. A subclass answers
  # two private methods:
  #
  #   source      the name of the API, for the log
  #   uri(...)    the URI of one request
  class JsonApi
    # The parsed answer of one request. Raises FetchError when the request
    # failed or the answer is not JSON.
    def get(...)
      JSON.parse(Http.get(uri(...), source:))
    rescue JSON::ParserError => e
      raise FetchError, "cannot parse the answer of #{source} (#{e.message})"
    end
  end
end
