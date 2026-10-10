require 'net/http'

require 'providers/fetch_error'
require 'user_agent'

module Providers
  # One GET against a remote source, shared by every provider.
  #
  # The error messages name the source, never the URI. A URI can carry a
  # query string with settings of the user in it, and a message that printed
  # the URI would write those into the log.
  module Http
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    # The body of a successful response. Raises FetchError when the
    # request failed.
    def self.get(uri, source:)
      request(uri, source:, &:body)
    end

    # Writes the body of a successful response into `io`, chunk by chunk,
    # so that no string holds all of it. Raises FetchError when the request
    # failed.
    def self.download(uri, io, source:)
      request(uri, source:) { |response| response.read_body { |chunk| io.write(chunk) } }
      nil
    end

    # Yields the response once its status is known and before its body is
    # read, and answers what the block answers.
    def self.request(uri, source:)
      result = nil

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
      ) do |http|
        http.request(Net::HTTP::Get.new(uri, 'User-Agent' => UserAgent.current)) do |response|
          check(response, source)
          result = yield response
        end
      end

      result
    rescue FetchError
      raise
    rescue StandardError => e
      raise FetchError, "#{e.class} from #{uri.host}: #{e.message}"
    end

    def self.check(response, source)
      case response
      when Net::HTTPSuccess
        nil
      when Net::HTTPTooManyRequests
        raise FetchError.new(
          "#{response.code} from #{source}, rate limit reached, " \
          "retry after #{response['Retry-After'] || '?'} seconds",
          status: response.code.to_i,
        )
      else
        raise FetchError.new("#{response.code} #{response.message} from #{source}", status: response.code.to_i)
      end
    end

    private_class_method :request, :check
  end
end
