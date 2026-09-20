require 'app_version'

# User agent sent with every outgoing HTTP request, so the data sources can
# identify the collector and its version.
module UserAgent
  APP_NAME = 'SOLECTRUS/Public-Data-Collector'.freeze
  HOMEPAGE = 'https://github.com/solectrus/public-data-collector'.freeze

  def self.current
    identifier = [APP_NAME, AppVersion.current].compact.join('/')

    "#{identifier} (+#{HOMEPAGE})"
  end
end
