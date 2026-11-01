# Development

This file is for developers. The [README](README.md) describes the collector for its users.

The collector reads several remote sources. A provider is the code that reads one source. Each provider has a folder of its own in `lib/providers`, with a README that describes its values for the users. The technical details of each provider are in the section [Providers](#providers) of this file.

Install the gems and run the tests:

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## How the collector runs

The collector runs a loop. One pass of the loop is a cycle, and it calls every provider that is due. Every provider reads at the start. After that, a provider reads on every cycle, or once a week:

- A provider that reads on every cycle wakes up every `INTERVAL` seconds. A provider can set a minimum for the interval, and the collector refuses a shorter interval.
- A weekly provider reads on its weekday at its hour, whatever the interval is. The collector wakes up at that hour, so the providers that read on every cycle also read then.

A read writes points that exist already again. They get the same value, so a repeated write costs nothing, and the next read repairs the data of a failed one.

A read fails when the source does not answer, answers with an error code, or sends data that the provider cannot read. It also fails when the write to InfluxDB fails. The failed provider tries again after one interval, and after each further failure, the wait doubles. A weekly provider also tries again at its weekday and hour. A source that fails for good, for example because it does not know the country, therefore costs few downloads.

## History

InfluxDB keeps a bucket in blocks of one week, which are called shards, and every shard uses memory and open files. A fuel price from 2005 in a bucket whose data begins in 2020 would add about 800 shards that hold nothing else. The collector therefore writes the history only from the time where the other data in the bucket begins.

At the start, the collector asks InfluxDB for the oldest point in the bucket. It does not count its own measurements. Then the history is written in two steps:

1. The first read of a provider writes its history from that time on, together with the newest value before it. That value tells the price at the time where the data begins.
2. Every later read writes a short window: eight weeks of fuel prices, eighteen months of gas prices, and today and tomorrow of the electricity values. A later read therefore does not write to every shard again.

Every start repeats the first read. For the fuel and gas prices, it reads the whole history again. For the electricity values, it reads only the days that InfluxDB does not hold yet, because their history is large. The section [Energy-Charts](#energy-charts) gives the details.

## Settings

The collector needs as few settings as possible. The measurements and the fields are fixed in the code, so SOLECTRUS finds the values without a configuration. A provider reads a setting only for what it cannot find out itself. Energy-Charts, for example, finds the bidding zone from `COUNTRY` and reads `BIDDING_ZONE` only for a country with more than one zone.

## Layout

The code has two parts. `lib` holds the program itself and knows no provider. `lib/providers` holds one folder per provider:

```
lib/main.rb                   the entry point and the banner
lib/config.rb                 the interval and the InfluxDB connection
lib/loop.rb                   the cycle: calls every provider, pushes its batches
lib/timetable.rb              when each provider reads next, and the wait after a failure
lib/flux_writer.rb            writes the batches to InfluxDB
lib/flux_reader.rb            finds where the other data in the bucket begins, and what it holds of each field

lib/providers/base.rb         base class of the providers
lib/providers/series.rb       base class of one value that a provider reads
lib/providers/schedule.rb     every cycle, or once a week
lib/providers/<name>/         one folder per provider
```

A provider folder holds everything of that source: its README, its settings, the client for the remote source, the reader for the format of the answer, and one series per value. The section [Providers](#providers) lists the files of each folder. Nothing of one provider reaches into another. The files outside the folders name no provider.

## How the loop calls a provider

Every provider has the same interface, which `Providers::Base` defines:

| Method         | Answers                                                  |
| -------------- | -------------------------------------------------------- |
| `.from_env`    | the provider, with its settings read from ENV            |
| `.switch`      | the key in ENV that turns the provider on                |
| `call`         | one `Batch` per value that arrived                       |
| `schedule`     | when it reads after the start, see `Providers::Schedule` |
| `descriptions` | one line per value for the banner                        |
| `measurements` | the measurements it writes to                            |

`Providers.from_env` loads every folder and builds every provider whose switch is `true`. It reads no settings of a provider that is off. If no provider is on, it raises `Env::Error`. The loop then calls `call` on each provider that is due, and gives every batch to `FluxWriter`. With each call, the loop passes the start of the history and tells whether it is the first read of the provider. At the first read, it also passes what the bucket holds of each field of the provider: the oldest point, and the newest point before today.

A batch is a measurement and a list of rows. Each row has a time and its fields. The writer therefore needs no knowledge of the records of a provider. A provider that reads more than one value keeps each value in a series of its own. The loop sees one provider and the batches that it answers, not the series.

## Adding a provider

To add a provider, add a folder below `lib/providers`. Nothing outside the folder changes. The folder holds these files:

1. `provider.rb` defines `Providers::<Name>::Provider`, a subclass of `Providers::Base`. It answers `.from_env`, `.switch`, `source`, and the private method `series`. The switch carries the name of the measurement, for example `ENABLE_FUEL` for `Fuel`. If the provider does not read on every cycle, it also answers `schedule`, for example `Schedule::Weekly.new(WEEKDAY, HOUR)`.
2. `settings.rb` defines `Providers::<Name>::Settings`, a `Data` object with `.from_env`. It reads the settings that the provider needs, and raises `Env::Error` for a missing value. The measurement and the fields are no settings: each series names them in the code.
3. One subclass of `Providers::Series` per value. `lib/providers/series.rb` lists the methods that a series answers. A series with a long history also answers `window`, the number of days that a read covers after the first read.
4. A client for the remote source, and a reader for the format of its answer if it is not JSON.
5. `README.md` describes the values for the users, in the shape of the other providers: what the collector writes, the values, the configuration, when the collector reads, and the license.
6. A section in [Providers](#providers) of this file, for the technical details.

`lib/providers/eurostat/provider.rb` is a short example. A record of a series is a `Data` object. It answers `starts_at` and one method per field that the series names in `fields`. A field without a value is left out of the row.

## Tests

The specs follow the same layout as `lib`. They make no request to a remote source. They replay the recorded answers in `spec/cassettes`, or build the answer themselves. The section of each provider in [Providers](#providers) tells how its specs get their data.

To record an answer again, delete its file in `spec/cassettes` and run the specs.

Every line of `lib` must be covered. `bundle exec rspec` fails when the coverage drops below 100 percent, and it names the file that lost it.

## Providers

### Energy-Charts

Each value has its current values and its history from different endpoints:

| Value           | Current values                         | History            |
| --------------- | -------------------------------------- | ------------------ |
| Day-ahead price | `/v2/price`, today and tomorrow        | `/v2/price`        |
| Renewable share | `/v2/signal`, today and tomorrow       | `/v2/public_power` |
| CO2 intensity   | `/v2/total_power`, yesterday and today | `/v2/total_power`  |

`/v2/signal` answers for today and the forecast alone. `/v2/public_power` carries the same share in the series `renewable_share_of_load`. On 2026-10-10, the two endpoints gave the same value for every quarter hour that was measured. The provider ignores the traffic light of `/v2/signal`, because it is coarse and its thresholds differ per country.

The CO2 intensity has no forecast. Its current values include yesterday, because the last quarter hours of a day arrive about two hours after midnight. `/v2/total_power` includes the power plants of the industry, as the UBA does. `/v2/public_power` leaves them out and gives a value that is 2 to 4 percent lower. `co2_series.rb` documents the factors and their derivation.

At the start, the loop passes the oldest point and the newest point before today of each field. The provider then reads two parts of the history:

1. The days from the start of the history until the oldest point. These are missing at the first start, and after an import of older data.
2. The days from one day before the newest point until yesterday. These are missing when the collector did not run for some time.

The second part starts one day early because of the forecast. Every cycle writes the share until the end of tomorrow, so InfluxDB holds forecast values for the day of the last cycle and the day after it. The second part replaces them with measured values. A gap in the middle of the history stays. If InfluxDB refuses the query, the provider reads the whole history.

The provider asks for one year per request, the newest year first. A year without data ends that part of the history. For such a year, `/v2/price` answers 404 and `/v2/public_power` answers 400. Each endpoint accepts 2 requests per minute, so the provider waits 31 seconds between two requests to the same endpoint. One year of `/v2/public_power` or `/v2/total_power` is about 20 MB, and the provider uses about 100 MB of memory while it reads it.

```
provider.rb       the provider: reads on every cycle, minimum interval 60 seconds
settings.rb       the settings, read from ENV
client.rb         the JSON client, the envelope that every endpoint answers with, and the wait between two requests
history.rb        the days before the current values, one year per request
price_series.rb   the day-ahead price, from /v2/price
share_series.rb   the renewable share, from /v2/signal, and from /v2/public_power for the history
co2_series.rb     the CO2 intensity, computed from /v2/total_power
```

The specs replay `spec/cassettes/energy_charts/price.yml`, `share.yml` and `co2.yml`. The specs of the history build their answers themselves, because one year of the share is 20 MB.

### Eurostat

The API answers in JSON-stat. This format keeps the values in one flat list and the labels of every dimension beside it. `json_stat.rb` reads it.

```
provider.rb           the provider: reads at the start and on Friday at 06:00
settings.rb           the settings, read from ENV
client.rb             the JSON client, one request per dataset
json_stat.rb          the reader for JSON-stat
gas_price_series.rb   the gas price: the months of the half years, and the months after the newest one
```

The specs replay `spec/cassettes/eurostat/gas_prices.yml`.

On macOS, the certificate of `ec.europa.eu` can fail to verify, because the system bundle does not have the GlobalSign Root R46. To record the cassette again, point Ruby at a current bundle:

```bash
SSL_CERT_FILE=/opt/homebrew/etc/ca-certificates/cert.pem bundle exec rspec
```

The Docker image has a current bundle, so this problem occurs on the development machine alone.

### EU Weekly Oil Bulletin

The bulletin is an XLSX file of about 4 MB behind a link that carries a UUID. In 2026, the UUID stayed the same while the file changed every week, but the Commission does not promise that. The provider therefore reads the page of the bulletin and finds the link by its file name.

The file has no ETag and no Last-Modified header, so every read downloads all of it. The server offers no compression, which would save only 6 percent of a ZIP archive. The unpacked sheet is about 9 MB. `xlsx.rb` therefore reads the XML one token at a time and never keeps the whole sheet in memory. The provider leaves out the two heavy fuel oils of the bulletin, because ships and industry use them.

```
provider.rb            the provider: reads at the start and on Friday at 06:00
settings.rb            the settings, read from ENV
client.rb              finds the file on the page, downloads it and reads the weeks
xlsx.rb                reads one sheet of an XLSX file, row by row
fuel_price_series.rb   the prices per litre, one record per week
```

The specs replay the page from `spec/cassettes/oil_bulletin/page.yml`. The file itself has no place in a repository, so the specs build their own file in the shape of the bulletin, with `spec/support/xlsx_builder.rb`.
