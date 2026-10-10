# Energy-Charts

This provider reads three values from the [Energy-Charts API](https://api.energy-charts.info/) of Fraunhofer ISE:

- The day-ahead electricity price, so you can run a load when electricity is cheap.
- The renewable share of the load, so you can run a load when the grid is green.
- The CO2 intensity of the power mix, so you can tell how much CO2 your grid import caused. This value exists for Germany alone.

The API reports the electricity market of more than 50 bidding zones in Europe. A bidding zone is an area with one common electricity price. The API needs no account and no key.

## What the provider writes

| Sensor                       | Unit    | Pace         |
| ---------------------------- | ------- | ------------ |
| `PublicGrid:price`           | EUR/kWh | quarter hour |
| `PublicGrid:renewable_share` | percent | quarter hour |
| `PublicGrid:co2_intensity`   | g/kWh   | quarter hour |

The table shows the default names. You can rename the measurement and every field.

## Configuration

| Variable                            | Default           | Description                                               |
| ----------------------------------- | ----------------- | --------------------------------------------------------- |
| `PUBLIC_GRID_BIDDING_ZONE`          | `DE-LU`           | Bidding zone, for example `DE-LU`, `AT`, `CH`, `FR`, `NL` |
| `PUBLIC_GRID_MEASUREMENT`           | `PublicGrid`      | Measurement that holds the electricity values             |
| `PUBLIC_GRID_FIELD_PRICE`           | `price`           | Field that holds the day-ahead price                      |
| `PUBLIC_GRID_FIELD_RENEWABLE_SHARE` | `renewable_share` | Field that holds the renewable share                      |
| `PUBLIC_GRID_FIELD_CO2_INTENSITY`   | `co2_intensity`   | Field that holds the CO2 intensity                        |

The share and the CO2 intensity also need the general setting `COUNTRY`. The provider computes the CO2 intensity only when `COUNTRY` is `DE`. The price does not use `COUNTRY`. It asks for the bidding zone in `PUBLIC_GRID_BIDDING_ZONE` instead.

### Finding your bidding zone or country

Open https://api.energy-charts.info/v2 and read the `allowed_values` of these parameters:

- The `bzn` parameter of `/v2/price`, for the bidding zone.
- The `country` parameter of `/v2/signal`, which is the endpoint that carries the share.

## How often the provider reads

The provider reads at the start, and then on every cycle, every `INTERVAL` seconds. The electricity price changes once a day, when the auction results appear. One hour is therefore enough, and a shorter interval reads the same numbers again. With the default of one hour, the collector gets the prices for tomorrow within an hour after their publication.

A cycle writes today and tomorrow again. A point that exists already gets the same value. A repeated write therefore costs nothing and repairs the data after a gap.

The price endpoint accepts 2 requests per minute. One cycle makes one request per endpoint, so the collector refuses an interval below 60 seconds.

## History

The first read after a start also writes the days before the current values that InfluxDB does not hold yet. The history begins where the other data in your bucket begins. The section [History](../../../README.md#history) explains why. Every later read writes today and tomorrow alone.

The history of each value comes from a different endpoint than its current values:

| Value           | Current values                         | Days before        | Begins for Germany |
| --------------- | -------------------------------------- | ------------------ | ------------------ |
| Day-ahead price | `/v2/price`, today and tomorrow        | `/v2/price`        | 2018-10-01         |
| Renewable share | `/v2/signal`, today and tomorrow       | `/v2/public_power` | 2015-01-01         |
| CO2 intensity   | `/v2/total_power`, yesterday and today | `/v2/total_power`  | 2015-01-01         |

The CO2 intensity has no forecast. Its current values include yesterday, because the last quarter hours of a day arrive about two hours after midnight.

`/v2/signal` answers for today and the forecast alone. `/v2/public_power` carries the same share in the series `renewable_share_of_load`. On 2026-10-10, the two endpoints gave the same value for every quarter hour that was measured. They differed only where `/v2/signal` used its forecast.

Until 30 September 2025, the day-ahead auction set one price per hour. The history therefore has one price per hour until that day, and one price per quarter hour after it.

### Which days a start reads

At the start, the collector asks InfluxDB for two points of each field: the oldest point, and the newest point before today. The provider then reads two parts of the history:

1. The days from the start of the history until the oldest point. These are missing at the first start, and after you import older data into the bucket.
2. The days from one day before the newest point until yesterday. These are missing when the collector did not run for some time.

The second part starts one day early because of the forecast. Every cycle writes the share until the end of tomorrow. For the day of the last cycle and the day after it, InfluxDB therefore holds forecast values. The second part replaces them with measured values. After a short restart, the second part is two days.

A gap in the middle of the history stays. Such a gap occurs when a source fails for more than a day while the collector runs.

If InfluxDB refuses the query, the provider reads the whole history.

### Requests

The provider asks for one year per request, the newest year first. A year without data ends that part of the history. For such a year, the price endpoint answers 404 and `/v2/public_power` answers 400. The read continues with today and tomorrow. If the source fails for another reason, the read fails, and the next cycle tries again.

Each endpoint accepts 2 requests per minute. The provider therefore waits 31 seconds between two requests to the same endpoint. A history of six years takes about nine minutes at the first start, because the three values read one after the other.

### Size

The history of the renewable share is large. `/v2/public_power` sends every kind of generation together with the share, and it cannot leave them out. One year is a download of about 20 MB. While the provider reads one year, it uses about 100 MB of memory. One year of prices is less than 3 MB.

The history of the CO2 intensity has the same size, because `/v2/total_power` also sends every source. If the data in your bucket begins in 2020, the first start downloads about 260 MB. A later start downloads only the missing days, which is less than 1 MB after a short restart.

## Day-ahead electricity price

The day-ahead price is the price of the spot market auction for the next day. The auction runs once a day, and the results appear in the early afternoon CET. Before that time, the source returns today alone.

The provider writes one point per quarter hour. The timestamp is the start of the quarter hour. The value is the price per kWh. The source reports a price per MWh, and the provider divides it by 1000.

The price is the net exchange price. It does not contain grid fees, levies, or tax. Your supplier adds those to the price you pay.

### Do not mix these prices with the prices of tibber-collector

[tibber-collector](https://github.com/solectrus/tibber-collector) writes to the measurement `Prices` by default. This provider writes to `PublicGrid`, so the two do not collide when they write to the same InfluxDB.

The two prices are not the same number. Tibber reports the price you pay, with grid fees, levies, and tax. This provider reports the exchange price without them. A point of one collector in the measurement of the other is wrong data. It is hard to find later, because both carry the same timestamps.

You can replace `tibber-collector` with this collector, for example together with the [SENEC Charger](https://github.com/solectrus/senec-charger). To do that, set `PUBLIC_GRID_MEASUREMENT=Prices` and `PUBLIC_GRID_FIELD_PRICE=amount`, because `tibber-collector` uses those two names. The renewable share then goes to `Prices` as well, in the field `renewable_share`.

Do not run both collectors with that configuration at the same time. The second one overwrites the points of the first one.

## Renewable share of the load

The share tells how much of the load renewable sources cover. It reaches from today until the end of the forecast, which is usually the end of tomorrow. It answers a question that the price cannot answer: when you take power from the grid, how much of it is renewable at that moment.

The provider writes one point per quarter hour. The value is the renewable share of the load in percent.

### One measurement for the two electricity values

The price and the share go to one measurement, in two fields. InfluxDB stores a measurement as a table, with one row per timestamp and one column per field. Both values carry the same quarter hour timestamps, so they fill two columns of the same row.

SOLECTRUS reads each value as a separate sensor. A sensor names the measurement and the field, for example `PublicGrid:price` or `PublicGrid:renewable_share`. Two measurements give you nothing that these two names do not give you.

The name tells what the data is, not where it comes from. Both values describe the public grid: what the electricity costs there, and how much of it is renewable. Neither value describes your own system. The name therefore stays clear of the `grid_import_power` and `grid_export_power` sensors, which measure your own meter.

The field is `renewable_share` and not `share`, because the source also offers a solar share and a wind share. A later version can add them without a rename.

`PUBLIC_GRID_FIELD_PRICE` and `PUBLIC_GRID_FIELD_RENEWABLE_SHARE` must differ. One name for both makes one value overwrite the other, so the collector stops at the start in that case.

### The share can go above 100

The share is the renewable generation divided by the load. It goes above 100 percent when wind and sun produce more than the country consumes at that moment. The surplus goes to export or to storage. On 2026-09-19, the share for Germany reached 132.8 percent in the afternoon.

Do not treat a value above 100 as an error, and do not cap a gauge at 100. Half of the values of that day were above it.

The share of generation is a different number, and it stays at or below 100. The source reports it in `/v2/public_power` as `renewable_share_of_generation`. This provider does not read it, because it does not tell whether the renewable power covers the load.

### The traffic signal is not collected

The same answer carries a traffic light with the values -1, 0, 1 and 2. The provider ignores it, for three reasons.

The light is coarse. On 2026-09-19, it was 2 (green) for all 192 quarter hours in Germany. In the same period, the share moved between 75.7 and 132.8 percent. A user who picks an hour inside a day learns nothing from it.

The thresholds are not published, and they differ per country. A measurement on 2026-09-19 gave green above about 27 percent in the Netherlands and above about 95 percent in Austria. The light of two countries is not comparable.

The light carries no information that the share does not carry. If you want a light, you can compute it from the share, with thresholds that you choose.

## CO2 intensity

The CO2 intensity tells how many grams of CO2 the generation of one kWh caused, for each quarter hour. It answers how much CO2 your grid import caused, which a fixed factor for every hour cannot answer. In 2025, the value was between 92 and 737 g/kWh, with a median of 359 g/kWh.

### Definition

The value follows the definition of the "Emissionsfaktor Strommix" of the Umweltbundesamt (UBA), the federal environment agency of Germany:

- It counts the direct CO2 from the combustion of fuel. It does not count the emissions upstream, for example from mining, and it does not count methane or nitrous oxide.
- It divides by the consumption, which is the generation less the losses of the grid.
- It counts the generation in Germany alone. Imports and exports do not change it.
- It counts biomass as zero, as the reporting rules require.

### Computation

Energy-Charts reports no CO2 value. The provider computes it from two inputs:

1. The net generation of every source per quarter hour, from `/v2/total_power`. This endpoint includes the power plants of the industry, as the UBA does.
2. One emission factor per fuel, in gram CO2 per kWh. The UBA publishes the emissions per fuel and the energy per fuel each year. The ratio of the two, related to the energy that Energy-Charts reports, gives the factor.

| Fuel                | Factor in g/kWh |
| ------------------- | --------------- |
| Lignite             | 1100            |
| Hard coal           | 862             |
| Natural gas         | 390             |
| Oil                 | 770             |
| Waste               | 830             |
| Other fuels         | 1090            |
| Renewables, nuclear | 0               |

The factors are the average of 2023, 2024 and 2025. For coal and gas, the factors of the three years differ by 1 percent or less. The factor for waste is about half of the UBA value, because the UBA counts the fossil part of waste alone, and Energy-Charts reports all of it.

The provider divides the emissions by the generation less pumping, times 0.947. The UBA consumption was 94.7 percent of that generation in each of the three years.

A quarter hour without a value for one of the main sources gets no value. This is true for the newest quarter hours of an answer.

### Accuracy

The yearly average of the computed values, weighted with the consumption, matches the value of the UBA within 1.6 percent:

| Year | UBA in g/kWh | Computed | Difference |
| ---- | ------------ | -------- | ---------- |
| 2015 | 529          | 527      | -0.5 %     |
| 2016 | 524          | 524      | -0.1 %     |
| 2017 | 490          | 492      | +0.5 %     |
| 2018 | 473          | 480      | +1.6 %     |
| 2019 | 409          | 408      | -0.4 %     |
| 2020 | 365          | 362      | -0.8 %     |
| 2021 | 406          | 404      | -0.4 %     |
| 2022 | 433          | 434      | +0.1 %     |
| 2023 | 379          | 378      | -0.2 %     |
| 2024 | 353          | 351      | -0.6 %     |
| 2025 | 344          | 342      | -0.7 %     |

The UBA values come from [Climate Change 16/2026](https://www.umweltbundesamt.de/publikationen/entwicklung-der-spezifischen-treibhausgas-0), table 1. The values for 2024 and 2025 are preliminary. The factors come from 2023 to 2025, so 2015 to 2022 test the method on years that it did not learn from.

In these eleven years, the value for Germany fell from 529 to 344 g/kWh. The mix of sources explains this fall, and the provider reads the mix for each quarter hour. The factor of each fuel changed so little that one set of factors fits every year.

With `/v2/public_power`, the result is 2 to 4 percent lower, because that endpoint leaves out the power plants of the industry. No official value exists for that mix, so the provider uses `/v2/total_power`.

### Limits

- The factors describe the power plants of Germany. For another country, the provider writes no CO2 intensity.
- The UBA publishes new values each March. If the power plants change, the factors must change, and only values written after that change use the new factors.
- Energy-Charts replaces preliminary data with final data later. The provider does not read a day again after it wrote it.
- The UBA values hold for a year. A single quarter hour has no official value to compare with.

## Data source

The values have different origins. Every answer names its own origin in a `license` field.

The license of the price depends on the bidding zone. Energy-Charts passes the number through without a change. On 2026-10-10, the answers named two licenses:

| License                                       | Bidding zones, among others                                                              |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| CC BY 4.0, from Bundesnetzagentur \| SMARD.de | `DE-LU`, `AT`, `BE`, `CH`, `CZ`, `DK1`, `DK2`, `FR`, `HU`, `NL`, `PL`, `SI`              |
| For private and internal use alone            | `ES`, `FI`, `GR`, `PT`, `EE`, `SK`, `SE1` to `SE3`, the zones of Italy except `IT-North` |

The collector writes the price into your own InfluxDB, which is a private use. If you pass the price on to other people, read the license of your zone first.

The renewable share comes from [Energy-Charts](https://www.energy-charts.info/) itself, under CC BY 4.0 with attribution to energy-charts.info. This is true for `/v2/signal`, `/v2/public_power` and `/v2/total_power`. Fraunhofer ISE computes the share from generation and load data. The part that reaches into the future is their forecast, not a measurement.

The CO2 intensity is a computation of the collector. It uses the generation from `/v2/total_power` and emission factors derived from the publications of the Umweltbundesamt, see [CO2 intensity](#co2-intensity).

## Files

```
provider.rb       the provider: reads on every cycle, minimum interval 60 seconds
settings.rb       the settings, read from ENV
client.rb         the JSON client, the envelope that every endpoint answers with, and the wait between two requests
history.rb        the days before the current values, one year per request
price_series.rb   the day-ahead price, from /v2/price
share_series.rb   the renewable share, from /v2/signal, and from /v2/public_power for the history
co2_series.rb     the CO2 intensity, computed from /v2/total_power
```

The specs replay the recorded answers `spec/cassettes/energy_charts/price.yml`, `spec/cassettes/energy_charts/share.yml` and `spec/cassettes/energy_charts/co2.yml`. To record them again, delete the files and run the specs. The specs of the history do not use recorded answers, because one year of the share is 20 MB.
