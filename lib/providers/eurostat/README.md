# Eurostat

This provider reads the price of natural gas from the [dissemination API](https://ec.europa.eu/eurostat/web/main/data/web-services) of Eurostat. With it, you can compare a gas heating with a heat pump.

Eurostat is the statistical office of the European Union. The API needs no account and no key. It answers in JSON-stat, a format that keeps the values in one flat list and the labels of every dimension beside it.

## What the provider writes

| Sensor      | Unit    | Pace  |
| ----------- | ------- | ----- |
| `Gas:price` | EUR/kWh | month |

The table shows the default name. You can rename the measurement. The field name is fixed.

## Configuration

| Variable          | Default | Description                 |
| ----------------- | ------- | --------------------------- |
| `GAS_MEASUREMENT` | `Gas`   | Measurement for natural gas |

The provider also needs the general setting `COUNTRY`. Eurostat writes Greece as `EL`, and the provider passes the code without a change.

Countries outside the European Union are not in Eurostat. For such a country, every read logs an error for the gas price, and the other values continue.

## How often the provider reads

The provider reads at the start, and then once a week on Friday at 06:00, whatever the interval is. The time is in the timezone that `TZ` sets. The read at the start fills InfluxDB at once for a new container.

Eurostat publishes the measured price twice a year. A second dataset shows how the price moved after that, and it arrives once a month. The section [Two datasets](#two-datasets-because-one-alone-is-either-exact-or-current) explains both. A weekly read is therefore enough.

The series reaches back to 2007. The first read after a start writes the months from the time where the other data in your bucket begins. The section [History](../../../README.md#history) explains why. Every later read writes the last eighteen months. A new half year replaces values that are up to one year old, and the other six months are a margin for a late publication.

If a read fails, the next read repairs the data.

## Natural gas

Eurostat publishes the price of natural gas as an average price per kWh for consumption band D2. That band is 20 to 199 gigajoule a year, or 5556 to 55556 kWh, which covers a house. The price includes every tax and levy.

The standing charge is already in that number. Eurostat spreads the monthly charge over the kWh of the band. A comparison that adds the charge again counts it twice. A comparison that leaves it out makes gas look cheaper than it is.

### Two datasets, because one alone is either exact or current

Eurostat measures the price twice a year and publishes it about six months later. Taken alone, that value can be fifteen months old, which is a long time in a moving market.

The provider therefore reads a second dataset, the Harmonised Index of Consumer Prices (HICP) for natural gas. A price index is a number that shows how a price changes over time. It is not the price itself. Eurostat publishes the HICP every month, about three weeks after the end of the month.

The provider asks for the HICP with the average of 2015 as 100. A value of 178 means that households paid 78 percent more than in 2015. Eurostat also publishes the HICP with 2025 as 100. The choice of the base year does not change the result, because the provider uses only the ratio of two index values.

| Dataset         | Holds                                  | Published    |
| --------------- | -------------------------------------- | ------------ |
| `nrg_pc_202`    | the price per kWh                      | twice a year |
| `prc_hicp_minr` | the price index, which shows the moves | every month  |

The provider writes the measured price of every half year into each of its six months. Then it carries the newest half year forward with the index, one value per month:

1. It takes the price of the newest half year.
2. It calculates the average index over the months of that half year. This average is the base.
3. For every month after that half year, it divides the index of the month by the base. It multiplies the price of the half year by the result.

The measured price is an average over six months. The base is an average over the same six months. The first carried month therefore continues where the measured price ends. A value up to fifteen months old becomes one about three weeks old.

This example uses the data of Eurostat for Germany, as of September 2026. It calculates the price for July 2026:

| Step | What                                                   | Value          |
| ---- | ------------------------------------------------------ | -------------- |
| 1    | The measured price for the second half of 2025         | 0.1223 EUR/kWh |
| 2    | The base: the average index from July to December 2025 | 178.58         |
| 3    | The index for July 2026                                | 173.39         |
|      | The index divided by the base: 173.39 / 178.58         | 0.971          |
|      | The price multiplied by that: 0.1223 × 0.971           | 0.1188 EUR/kWh |

The index fell by 2.9 percent compared with the base. The price for July 2026 is therefore 2.9 percent lower than the measured price.

The carried months are a calculation, not a measurement. The index measures what all households pay, running contracts included. It therefore moves slower than the price that a new customer gets today.

If the request for the index fails, the provider writes the half years alone. The gas price then stays correct, but it is older.

### Values in the past can change

Every read writes the last eighteen months again. The values of past months can therefore change in InfluxDB:

- When Eurostat publishes a new half year, the provider writes its measured price into its six months. These points replace the carried values that earlier reads wrote there.
- The provider then carries the new half year forward. The months after it get new calculated values.
- When Eurostat corrects a value of the last eighteen months, the next read writes the corrected value. If the value is older, the next start writes it.

The months before the newest measured half year change only when Eurostat corrects a value.

For Germany, the carried price differed from the price that Eurostat measured later by 1.9 percent in the median. This covers the 22 half years from 2015 to 2025. During the energy crisis, the difference was up to 15 percent. For the first half of 2023, the carried price was 0.1044 EUR/kWh and the measured price 0.1230 EUR/kWh.

An evaluation of the newest months can therefore change when Eurostat publishes the next half year. An example is the cost of a gas heating compared with a heat pump.

## Data source

Natural gas comes from [Eurostat](https://ec.europa.eu/eurostat/databrowser/view/nrg_pc_202/default/table?lang=en), datasets `nrg_pc_202` and `prc_hicp_minr`. Reuse is free when the source is named. Eurostat does not measure the prices itself. The statistical office of every member state does, and Germany reports them through Destatis.

## Files

```
provider.rb           the provider: reads at the start and on Friday at 06:00
settings.rb           the settings, read from ENV
client.rb             the JSON client, one request per dataset
json_stat.rb          the reader for JSON-stat
gas_price_series.rb   the gas price: the months of the half years, and the months after the newest one
```

The specs replay the recorded answer `spec/cassettes/eurostat/gas_prices.yml`. To record it again, delete the file and run the specs.

On macOS, the certificate of `ec.europa.eu` can fail to verify, because the system bundle does not have the GlobalSign Root R46. To record the cassette again, point Ruby at a current bundle:

```bash
SSL_CERT_FILE=/opt/homebrew/etc/ca-certificates/cert.pem bundle exec rspec
```

The Docker image has a current bundle, so this problem occurs on the development machine alone.
