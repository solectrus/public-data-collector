require 'uri'

require 'env'

# The settings of the collector itself, read from ENV once at boot: the
# cycle and the InfluxDB connection.
#
# Nothing in here belongs to a provider. Every provider reads its own
# settings, see Providers::Base.
Config =
  Data.define(
    :interval,
    :influx_schema,
    :influx_host,
    :influx_port,
    :influx_token,
    :influx_org,
    :influx_bucket,
  ) do
    def initialize(**)
      super

      validate_url!
    end

    def influx_url
      "#{influx_schema}://#{influx_host}:#{influx_port}"
    end

    # Every provider checks the interval against its own minimum, see
    # Providers.from_env.
    def self.from_env(**)
      new(
        interval: (Env['INTERVAL'] || '3600').to_i,
        influx_host: Env.fetch('INFLUX_HOST'),
        influx_schema: Env['INFLUX_SCHEMA'] || 'http',
        influx_port: Env['INFLUX_PORT'] || '8086',
        influx_token: Env.fetch('INFLUX_TOKEN'),
        influx_org: Env.fetch('INFLUX_ORG'),
        influx_bucket: Env.fetch('INFLUX_BUCKET'),
        **,
      )
    end

    private

    def validate_url!
      uri = URI.parse(influx_url)
      return if uri.is_a?(URI::HTTP) && !uri.host.nil?

      raise Env::Error, "URL is invalid: #{influx_url}"
    end
  end
