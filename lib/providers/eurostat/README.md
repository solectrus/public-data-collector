# Eurostat

The collector reads the price of natural gas from the [dissemination API](https://ec.europa.eu/eurostat/web/main/data/web-services) of Eurostat. With it, you can compare the cost of a gas heating with a heat pump.

Eurostat is the statistical office of the European Union. The API needs no account and no key.

## What the collector writes

| Measurement | Field   | Value             | Unit    | One value per |
| ----------- | ------- | ----------------- | ------- | ------------- |
| `Gas`       | `price` | Natural gas price | EUR/kWh | month         |

The table shows the default names. You can change the measurement. The field name is fixed.

## The value

### Natural gas price

The price is the average price per kWh that households pay for natural gas. It includes every tax and levy. Eurostat reports it for the consumption band D2, which is 5556 to 55556 kWh a year and covers a house.

The standing charge is already in that number, because Eurostat spreads it over the kWh of the band. If you add the standing charge again, you count it twice. If you leave it out, gas looks cheaper than it is.

### Two datasets: the measured price and an index

Eurostat measures the price twice a year, for each half year, and publishes it about six months later. Taken alone, the newest price can therefore be fifteen months old.

The collector therefore reads a second dataset, the Harmonised Index of Consumer Prices (HICP) for natural gas. A price index is a number that shows how a price changes over time. It is not the price itself. Eurostat publishes the HICP every month, about three weeks after the end of the month.

| Dataset         | Holds                    | Published    |
| --------------- | ------------------------ | ------------ |
| `nrg_pc_202`    | the measured price       | twice a year |
| `prc_hicp_minr` | the price index for HICP | every month  |

The collector writes the measured price of each half year into each of its six months. For the months after the newest half year, it carries the price forward: it changes the price by the same ratio as the index changed. The newest price is then about three weeks old instead of up to fifteen months.

This example uses the data of Eurostat for Germany, as of September 2026. It calculates the price for July 2026:

| Step | What                                                      | Value          |
| ---- | --------------------------------------------------------- | -------------- |
| 1    | The measured price for the second half of 2025            | 0.1223 EUR/kWh |
| 2    | The average index from July to December 2025              | 178.58         |
| 3    | The index for July 2026                                   | 173.39         |
| 4    | The change of the index: 173.39 / 178.58                  | 0.971          |
| 5    | The measured price, changed by that ratio: 0.1223 × 0.971 | 0.1188 EUR/kWh |

A carried price is an estimate, not a measurement. The index measures what all households pay, running contracts included. It therefore moves slower than the price that a new customer gets today. If Eurostat does not deliver the index, the collector writes the measured prices alone.

### Values in the past can change

When Eurostat publishes a new half year, its measured price replaces the carried prices of its six months. The months after it get new carried prices. An evaluation of the newest months can therefore change, for example the cost of a gas heating compared with a heat pump.

For Germany, the carried price differed from the price that Eurostat measured later by 1.9 percent in the median, over the 22 half years from 2015 to 2025. During the energy crisis, the difference was up to 15 percent.

## Configuration

| Variable          | Default | Description                 |
| ----------------- | ------- | --------------------------- |
| `GAS_MEASUREMENT` | `Gas`   | Measurement for natural gas |

The collector also needs the general setting `COUNTRY`. Countries outside the European Union are not in Eurostat. For such a country, the log shows an error for the gas price, and the other values continue.

## When the collector reads

The collector reads at each start, and then on Friday at 06:00 in the timezone that `TZ` sets. Eurostat publishes new data once a month or less, so a weekly read is enough.

At the first start, the collector also writes the history from the time where the other data in your bucket begins. The [README of the collector](../../../README.md#history) explains why. The prices go back to 2007.

Every later read writes the last eighteen months again. This includes a new half year, which replaces prices up to one year old, and a correction by Eurostat. A correction of an older month arrives with the next start.

## License

The price comes from [Eurostat](https://ec.europa.eu/eurostat/databrowser/view/nrg_pc_202/default/table?lang=en), datasets `nrg_pc_202` and `prc_hicp_minr`. Reuse is free when the source is named. The statistical office of each member state measures the prices, and Germany reports them through Destatis.
