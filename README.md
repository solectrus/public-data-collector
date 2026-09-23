[![Continuous integration](https://github.com/solectrus/public-data-collector/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/public-data-collector/actions/workflows/push.yml)

# Public-data collector

Collect prices and values from public sources and push them to InfluxDB. Every source is free. None of them needs an account or a key. The sources cover Europe.

The collector reads three sources. The code that reads one source is a provider. Each provider has a README that describes its values, its configuration and its source:

| Provider                                                       | Values                                       | Pace            |
| -------------------------------------------------------------- | -------------------------------------------- | --------------- |
| [Energy-Charts](lib/providers/energy_charts/README.md)         | day-ahead electricity price, renewable share | every cycle     |
| [Eurostat](lib/providers/eurostat/README.md)                   | natural gas                                  | Friday at 06:00 |
| [EU Weekly Oil Bulletin](lib/providers/oil_bulletin/README.md) | petrol, diesel, heating oil, LPG             | Friday at 06:00 |

Every provider also reads at every start, so a new container fills InfluxDB at once.

## What the collector writes

| Sensor                       | Unit    | Provider               |
| ---------------------------- | ------- | ---------------------- |
| `PublicGrid:price`           | EUR/kWh | Energy-Charts          |
| `PublicGrid:renewable_share` | percent | Energy-Charts          |
| `Gas:price`                  | EUR/kWh | Eurostat               |
| `Fuel:price_petrol`          | EUR/l   | EU Weekly Oil Bulletin |
| `Fuel:price_diesel`          | EUR/l   | EU Weekly Oil Bulletin |
| `Fuel:price_heating_oil`     | EUR/l   | EU Weekly Oil Bulletin |
| `Fuel:price_lpg`             | EUR/l   | EU Weekly Oil Bulletin |

The table shows the default names. The README of each provider tells which names you can change.

## Configuration

The collector reads its configuration from environment variables. The general settings apply to every provider:

| Variable        | Default | Description                                    |
| --------------- | ------- | ---------------------------------------------- |
| `COUNTRY`       |         | Country code, for example `DE`, required       |
| `INTERVAL`      | `3600`  | Seconds between two cycles, minimum 60         |
| `INFLUX_HOST`   |         | Host of your InfluxDB, required                |
| `INFLUX_SCHEMA` | `http`  | `http` or `https`                              |
| `INFLUX_PORT`   | `8086`  | Port of your InfluxDB                          |
| `INFLUX_TOKEN`  |         | Token with read and write permission, required |
| `INFLUX_ORG`    |         | Organization in your InfluxDB, required        |
| `INFLUX_BUCKET` |         | Bucket in your InfluxDB, required              |
| `TZ`            |         | Timezone, for example `Europe/Berlin`          |

The collector writes with the token, and it reads with it once at the start. The section [History](#history) explains why.

Every kind of value has its own group of settings: `PUBLIC_GRID_*`, `GAS_*` and `FUEL_*`. A group is named after the value, not after the provider. A later version can then read a value from a different source, and your configuration stays the same. The README of each provider lists its settings. `.env.example` shows all settings in these groups.

The collector reads every value. If a source does not have a value for your country, the collector logs an error, and the other values continue.

### How often the collector runs

Every provider reads at the start, so a new container fills InfluxDB at once. After that, a provider reads on every cycle, or once a week:

- A provider that reads on every cycle wakes up every `INTERVAL` seconds. A provider can set a minimum for the interval, and the collector refuses a shorter interval.
- A weekly provider reads on its weekday at its hour, whatever the interval is. The hour is in the timezone that `TZ` sets. The collector wakes up at that hour, so the providers that read on every cycle also read then.

A read writes points that exist already again. They get the same value, so a repeated write costs nothing. If a read fails, the next read repairs the data.

If a read fails, the provider tries again after one interval. After each further failure, the wait doubles. A weekly provider also tries again at its weekday and hour. A source that fails for good, for example because it does not know your country, therefore costs few downloads.

A read fails when the source does not answer, answers with an error code, or sends data that the provider cannot read. It also fails when the write to InfluxDB fails. The log then shows the reason, and the collector continues with the other providers. In the next cycle, the collector reads the failed provider again. This is also true for a weekly provider, so it does not wait a full week.

### History

Two providers have a long history. The fuel prices go back to 2005, and the gas price goes back to 2007. The collector writes this history only from the time where the other data in your bucket begins.

The reason is the storage of InfluxDB. InfluxDB keeps the points of a bucket in blocks that are called shards. With an unlimited retention, one shard covers one week. Every shard uses memory and open files for as long as it exists. A fuel price from 2005 in a bucket whose data begins in 2020 therefore adds about 800 shards that hold nothing else.

At the start, the collector asks InfluxDB for the oldest point in the bucket. It does not count its own measurements. The log shows the result. Then the history is written in two steps:

1. The first read of a provider writes its history from that time on, together with the newest value before it. That value tells the price at the time where your data begins.
2. Every later read writes a short window: eight weeks of fuel prices, and eighteen months of gas prices. A weekly read therefore does not write to every shard again.

For the query at the start, the token needs read permission for the bucket. If the token can only write, the collector writes the newest value of each provider and no history. The same is true for a bucket that holds no other data. The log then tells the reason.

If you import older data into the bucket later, restart the collector. It then finds the new start and fills the history.

## Usage

1. Prepare an `.env` file. Use `.env.example` as the starting point.

2. Run the Docker containers on your Linux box:

   ```bash
   docker compose up
   ```

It is recommended to add `public-data-collector` to your [SOLECTRUS hosting](https://github.com/solectrus/hosting).

## Development

Install the gems and run the tests:

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

### Layout

The code has two parts. `lib` holds the program itself and knows no provider. A provider is the code that reads one remote source. Each provider has a folder of its own in `lib/providers`:

```
lib/main.rb                   the entry point and the banner
lib/config.rb                 the interval and the InfluxDB connection
lib/env.rb                    reads a setting out of ENV
lib/loop.rb                   the cycle: calls every provider, pushes its batches
lib/batch.rb                  what a provider hands to the writer
lib/flux_writer.rb            writes the batches to InfluxDB
lib/flux_reader.rb            finds where the other data in the bucket begins
lib/influx_client.rb          the InfluxDB client that the writer and the reader share
lib/app_version.rb            the version of this build
lib/user_agent.rb             what the collector calls itself

lib/providers.rb              loads every provider folder
lib/providers/base.rb         base class of the providers
lib/providers/series.rb       base class of one value that a provider reads
lib/providers/http.rb         one GET, shared by every provider
lib/providers/json_api.rb     base class of the clients that read a JSON API
lib/providers/country.rb      the country code in ISO 3166 spelling

lib/providers/energy_charts/  provider.rb, settings.rb, client.rb, price_series.rb, share_series.rb
lib/providers/eurostat/       provider.rb, settings.rb, client.rb, gas_price_series.rb, json_stat.rb
lib/providers/oil_bulletin/   provider.rb, settings.rb, client.rb, fuel_price_series.rb, xlsx.rb
```

A provider folder holds everything of that source: its README, its settings, the client for the remote source, the reader for the format of the answer, and one series per value. Nothing of one provider reaches into another. The files outside the folders name no provider.

### How the loop calls a provider

Every provider has the same interface, which `Providers::Base` defines:

| Method         | Answers                                                  |
| -------------- | -------------------------------------------------------- |
| `.from_env`    | the provider, with its settings read from ENV            |
| `call`         | one `Batch` per value that arrived                       |
| `schedule`     | when it reads after the start, see `Providers::Schedule` |
| `descriptions` | one line per value for the banner                        |
| `measurements` | the measurements it writes to                            |

`Providers.from_env` loads every folder and builds every provider. The loop then calls `call` on each provider that is due, and gives every batch to `FluxWriter`. With each call, the loop passes the start of the history and tells whether it is the first read of the provider.

A batch is a measurement and a list of rows. Each row has a time and its fields. The writer therefore needs no knowledge of the records of a provider.

A provider that reads more than one value keeps each value in a series of its own. Energy-Charts has two series, the price and the share. The loop sees one provider and the batches that it answers, not the series.

### Adding a provider

To add a provider, add a folder below `lib/providers`. Nothing outside the folder changes. The folder holds these files:

1. `provider.rb` defines `Providers::<Name>::Provider`, a subclass of `Providers::Base`. It answers `.from_env`, `source`, and the private method `series`. If the provider does not read on every cycle, it also answers `schedule`, for example `Schedule::Weekly.new(WEEKDAY, HOUR)`.
2. `settings.rb` defines `Providers::<Name>::Settings`, a `Data` object with `.from_env`. It reads the names of the measurement and the fields, and raises `Env::Error` for a missing value. Each variable starts with the name of the value, for example `GAS_`, never with the name of the provider.
3. One subclass of `Providers::Series` per value. `lib/providers/series.rb` lists the methods that a series answers. A series with a long history also answers `window`, the number of days that a read covers after the first read.
4. A client for the remote source, and a reader for the format of its answer if it is not JSON.
5. `README.md` describes the values, the settings, the pace and the source, in the shape of the other providers.

This is the provider of Energy-Charts without its comments:

```ruby
class Provider < Base
  MINIMUM_INTERVAL = 60

  def self.from_env
    new(Settings.from_env)
  end

  def source = NAME
  def schedule = Schedule::EveryCycle.new(minimum_interval: MINIMUM_INTERVAL)

  private

  def series
    @series ||= [
      PriceSeries.new(settings),
      ShareSeries.new(settings)
    ]
  end
end
```

A record of a series is a `Data` object. It answers `starts_at` and one method per field that the series names in `fields`. A field without a value is left out of the row.

### Tests

The specs follow the same layout as `lib`. They make no request to a remote source. They replay the recorded answers in `spec/cassettes`, or build the answer themselves. The README of each provider tells how its specs get their data.

Every line of `lib` must be covered. `bundle exec rspec` fails when the coverage drops below 100 percent, and it names the file that lost it.

## Data sources

Each source has its own license. The README of each provider names the source and the terms of reuse.

## License

Copyright (c) 2026 Georg Ledermann, released under the MIT License
