# Energy-Charts

The collector reads three electricity values from the [Energy-Charts API](https://api.energy-charts.info/) of Fraunhofer ISE:

- The day-ahead price, so you can run a device such as a heat pump or a wallbox when electricity is cheap.
- The renewable share, so you can run a device when the electricity from the grid is green.
- The CO2 intensity, so you can tell how much CO2 your grid import caused and how much CO2 your PV system saved. This value exists for Germany alone.

The API needs no account and no key. It covers more than 50 bidding zones in Europe. A bidding zone is an area with one common electricity price, for example `DE-LU` for Germany and Luxembourg.

## What the collector writes

| Measurement  | Field             | Value           | Unit    | One value per |
| ------------ | ----------------- | --------------- | ------- | ------------- |
| `PublicGrid` | `price`           | Day-ahead price | EUR/kWh | quarter hour  |
| `PublicGrid` | `renewable_share` | Renewable share | percent | quarter hour  |
| `PublicGrid` | `co2_intensity`   | CO2 intensity   | g/kWh   | quarter hour  |

The table shows the default names. You can change the measurement and every field. Each point has the start of its quarter hour as its time.

## The values

### Day-ahead price

The day-ahead price is the result of the auction at the power exchange for the next day. The auction runs once a day, and the results appear in the early afternoon. Before that time, the price for today is the newest value.

The price is the exchange price. It does not contain grid fees, levies, or tax. Your supplier adds those to the price you pay.

Until 30 September 2025, the auction set one price per hour. The history therefore has one value per hour until that day.

### Do not mix the price with the price of tibber-collector

[tibber-collector](https://github.com/solectrus/tibber-collector) writes the price that you pay to Tibber, with grid fees, levies, and tax. This collector writes the exchange price without them. The two prices are different numbers, so they go to different measurements: `Prices` for Tibber, `PublicGrid` for this collector.

You can use this collector instead of `tibber-collector`, for example for the [SENEC Charger](https://github.com/solectrus/senec-charger). To do that, set `PUBLIC_GRID_MEASUREMENT=Prices` and `PUBLIC_GRID_FIELD_PRICE=amount`. The renewable share and the CO2 intensity then go to `Prices` as well. Do not run both collectors with that configuration at the same time, because each one overwrites the prices of the other one.

### Renewable share

The renewable share tells how much of the electricity consumption in the country renewable sources cover. The values reach until the end of tomorrow. The values in the future are a forecast of Fraunhofer ISE.

The share goes above 100 percent when wind and sun produce more than the country consumes at that moment. On 2026-09-19, the share for Germany reached 132.8 percent in the afternoon. Do not treat a value above 100 as an error, and do not cap a gauge at 100.

### CO2 intensity

The CO2 intensity tells how many grams of CO2 the generation of one kWh caused in Germany, for each quarter hour. In 2025, the value was between 92 and 737 g/kWh, with a median of 359 g/kWh. The value has no forecast, and the newest value is about two hours old.

Energy-Charts reports no CO2 value, so the collector computes it. It takes the generation of each type of power plant and an emission factor for each fuel. The factors come from the Umweltbundesamt (UBA), the federal environment agency of Germany. For 2015 to 2025, the yearly average matches the official value of the UBA within 1.6 percent. The code in [co2_series.rb](co2_series.rb) documents the factors and the method.

To get the CO2 of your own energy, multiply the CO2 intensity of each quarter hour by your energy of the same quarter hour, and add the results:

- Grid import times CO2 intensity gives the CO2 that your grid import caused.
- PV generation times CO2 intensity gives the CO2 that your PV system saved, compared to electricity from the grid.

Do not multiply the energy of a whole day or year by an average value. The energy and the CO2 intensity change in the course of a day, so the result would be wrong.

The saved CO2 is a low estimate. PV generates the most energy at noon in summer, when the electricity from the grid is the cleanest. Also, a kWh from PV replaces mostly fossil power plants, which emit more than the average.

## Configuration

| Variable                            | Default           | Description                      |
| ----------------------------------- | ----------------- | -------------------------------- |
| `PUBLIC_GRID_BIDDING_ZONE`          | `DE-LU`           | Bidding zone of the price        |
| `PUBLIC_GRID_MEASUREMENT`           | `PublicGrid`      | Measurement for the three values |
| `PUBLIC_GRID_FIELD_PRICE`           | `price`           | Field for the day-ahead price    |
| `PUBLIC_GRID_FIELD_RENEWABLE_SHARE` | `renewable_share` | Field for the renewable share    |
| `PUBLIC_GRID_FIELD_CO2_INTENSITY`   | `co2_intensity`   | Field for the CO2 intensity      |

The price uses the bidding zone. The renewable share uses the general setting `COUNTRY`. The CO2 intensity exists only when `COUNTRY` is `DE`.

The three fields must have different names. If two names are the same, the collector stops at the start, because one value would overwrite the other.

Common bidding zones are `DE-LU`, `AT`, `BE`, `CH`, `CZ`, `DK1`, `DK2`, `FR`, `HU`, `NL`, `PL` and `SI`. To find another zone, open https://api.energy-charts.info/v2 and read the allowed values of the parameter `bzn` of `/v2/price`.

## When the collector reads

The collector reads at each start, and then every `INTERVAL` seconds. The price changes once a day, so the default of one hour is enough. The collector then gets the prices for tomorrow within one hour after the auction. The collector refuses an interval below 60 seconds, because Energy-Charts accepts only 2 requests per minute.

At the first start, the collector also writes the history from the time where the other data in your bucket begins. The [README of the collector](../../../README.md#history) explains why. For Germany, the price goes back to October 2018, and the renewable share and the CO2 intensity go back to 2015.

The first start is slow, because Energy-Charts accepts only a small number of requests. A history of six years takes about nine minutes. One year of the renewable share or of the CO2 intensity is a download of about 20 MB. If the data in your bucket begins in 2020, the first start downloads about 260 MB.

A later start reads only the days that are missing, for example after the collector did not run for some days. A gap in the middle of the history stays.

## License

The license of the price depends on the bidding zone. On 2026-10-10, Energy-Charts named two licenses:

| License                                       | Bidding zones, among others                                                              |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| CC BY 4.0, from Bundesnetzagentur \| SMARD.de | `DE-LU`, `AT`, `BE`, `CH`, `CZ`, `DK1`, `DK2`, `FR`, `HU`, `NL`, `PL`, `SI`              |
| For private and internal use alone            | `ES`, `FI`, `GR`, `PT`, `EE`, `SK`, `SE1` to `SE3`, the zones of Italy except `IT-North` |

The collector writes the price into your own InfluxDB, which is a private use. If you pass the price on to other people, read the license of your zone first.

The renewable share and the generation behind the CO2 intensity come from [Energy-Charts](https://www.energy-charts.info/) itself, under CC BY 4.0 with attribution to energy-charts.info.
