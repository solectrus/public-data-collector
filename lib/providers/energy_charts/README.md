# Energy-Charts

This provider reads two values from the [Energy-Charts API](https://api.energy-charts.info/) of Fraunhofer ISE:

- The day-ahead electricity price, so you can run a load when electricity is cheap.
- The renewable share of the load, so you can run a load when the grid is green.

The API reports the electricity market of more than 50 bidding zones in Europe. A bidding zone is an area with one common electricity price. The API needs no account and no key.

## What the provider writes

| Sensor                       | Unit    | Pace         |
| ---------------------------- | ------- | ------------ |
| `PublicGrid:price`           | EUR/kWh | quarter hour |
| `PublicGrid:renewable_share` | percent | quarter hour |

The table shows the default names. You can rename the measurement and both fields.

## Configuration

| Variable                            | Default           | Description                                               |
| ----------------------------------- | ----------------- | --------------------------------------------------------- |
| `PUBLIC_GRID_BIDDING_ZONE`          | `DE-LU`           | Bidding zone, for example `DE-LU`, `AT`, `CH`, `FR`, `NL` |
| `PUBLIC_GRID_MEASUREMENT`           | `PublicGrid`      | Measurement that holds the two electricity values         |
| `PUBLIC_GRID_FIELD_PRICE`           | `price`           | Field that holds the day-ahead price                      |
| `PUBLIC_GRID_FIELD_RENEWABLE_SHARE` | `renewable_share` | Field that holds the renewable share                      |

The share also needs the general setting `COUNTRY`. The price does not use it. It asks for the bidding zone in `PUBLIC_GRID_BIDDING_ZONE` instead.

### Finding your bidding zone or country

Open https://api.energy-charts.info/v2 and read the `allowed_values` of these parameters:

- The `bzn` parameter of `/v2/price`, for the bidding zone.
- The `country` parameter of `/v2/signal`, which is the endpoint that carries the share.

## How often the provider reads

The provider reads at the start, and then on every cycle, every `INTERVAL` seconds. The electricity price changes once a day, when the auction results appear. One hour is therefore enough, and a shorter interval reads the same numbers again. With the default of one hour, the collector gets the prices for tomorrow within an hour after their publication.

A cycle writes today and tomorrow again. A point that exists already gets the same value. A repeated write therefore costs nothing and repairs the data after a gap.

The price endpoint accepts 2 requests per minute. One cycle makes one request per endpoint, so the collector refuses an interval below 60 seconds.

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

### There is no CO2 value

The source carries no CO2 value, so the provider writes none. The renewable share is the closest number that it offers.

## Data source

The two values have different origins. Every answer names its own origin in a `license` field.

The price comes from Bundesnetzagentur | SMARD.de, for every bidding zone that the API offers. Energy-Charts passes the number through without a change. The license is CC BY 4.0.

The renewable share comes from [Energy-Charts](https://www.energy-charts.info/) itself, under CC BY 4.0 with attribution to energy-charts.info. Fraunhofer ISE computes it from generation and load data. The part that reaches into the future is their forecast, not a measurement.

## Files

```
provider.rb       the provider: reads on every cycle, minimum interval 60 seconds
settings.rb       the settings, read from ENV
client.rb         the JSON client and the envelope that every endpoint answers with
price_series.rb   the day-ahead price, from /v2/price
share_series.rb   the renewable share, from /v2/signal
```

The specs replay the recorded answers `spec/cassettes/energy_charts/price.yml` and `spec/cassettes/energy_charts/share.yml`. To record them again, delete the two files and run the specs.
