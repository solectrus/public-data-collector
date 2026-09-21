require 'influxdb-client'

# The client of InfluxDB. FluxWriter and FluxReader build it here, so both
# connect in the same way.
module InfluxClient
  def self.build(config)
    InfluxDB2::Client.new(
      config.influx_url,
      config.influx_token,
      use_ssl: config.influx_schema == 'https',
      precision: InfluxDB2::WritePrecision::SECOND,
    )
  end
end
