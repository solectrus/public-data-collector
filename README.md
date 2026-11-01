[![Continuous integration](https://github.com/solectrus/public-data-collector/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/public-data-collector/actions/workflows/push.yml)
[![Maintainability](https://qlty.sh/badges/109b5d7f-9e84-407f-8e90-4015d7ac54b5/maintainability.svg)](https://qlty.sh/gh/solectrus/projects/public-data-collector)
[![wakatime](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/488231c6-f912-4408-95fe-9d74ce0422b3.svg)](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/488231c6-f912-4408-95fe-9d74ce0422b3)
[![Code Coverage](https://qlty.sh/badges/109b5d7f-9e84-407f-8e90-4015d7ac54b5/coverage.svg)](https://qlty.sh/gh/solectrus/projects/public-data-collector)

# Public-data collector

The collector writes public prices and values into your InfluxDB. SOLECTRUS uses them to compare your costs and your CO2 with other sources of energy.

| Value           | Name in InfluxDB             | Unit    | Use in SOLECTRUS                      |
| --------------- | ---------------------------- | ------- | ------------------------------------- |
| Petrol          | `Fuel:price_petrol`          | EUR/l   | Compare electric and combustion cars  |
| Diesel          | `Fuel:price_diesel`          | EUR/l   | Compare electric and combustion cars  |
| LPG             | `Fuel:price_lpg`             | EUR/l   | Compare electric and combustion cars  |
| Heating oil     | `Fuel:price_heating_oil`     | EUR/l   | Compare heat pump and oil heating     |
| Natural gas     | `Gas:price`                  | EUR/kWh | Compare heat pump and gas heating     |
| Day-ahead price | `PublicGrid:price`           | EUR/kWh | Show when grid electricity is cheap   |
| Renewable share | `PublicGrid:renewable_share` | percent | Show when grid electricity is green   |
| CO2 intensity   | `PublicGrid:co2_intensity`   | g/kWh   | Calculate the CO2 of your grid import |

The day-ahead price is the price of electricity at the power exchange for the next day. The names in InfluxDB are fixed, so SOLECTRUS finds the values without a configuration.

The collector reads three sources. Each source is free and needs no account:

| Source                   | Values                           | Read   | Switch               |
| ------------------------ | -------------------------------- | ------ | -------------------- |
| [Weekly Oil Bulletin][1] | Petrol, diesel, LPG, heating oil | Weekly | `ENABLE_FUEL`        |
| [Eurostat][2]            | Natural gas                      | Weekly | `ENABLE_GAS`         |
| [Energy-Charts][3]       | Electricity                      | Hourly | `ENABLE_PUBLIC_GRID` |

[1]: https://energy.ec.europa.eu/data-and-analysis/weekly-oil-bulletin_en
[2]: https://ec.europa.eu/eurostat
[3]: https://www.energy-charts.info/

The European Commission publishes the Weekly Oil Bulletin. Eurostat is the statistical office of the European Union. Fraunhofer ISE, a German research institute, runs Energy-Charts. The sources cover the member states of the European Union. Eurostat and Energy-Charts also cover some other countries in Europe.

Energy-Charts reports no CO2 intensity, so the collector calculates it for Germany. It uses the power generation of each type of power plant from Energy-Charts, and the emission factors of the Umweltbundesamt, the federal environment agency of Germany.

Each source has a page with the details of its values: the [EU Weekly Oil Bulletin](lib/providers/oil_bulletin/README.md), [Eurostat](lib/providers/eurostat/README.md) and [Energy-Charts](lib/providers/energy_charts/README.md).

SOLECTRUS v1.4 (beta) uses only the petrol, diesel and LPG price. The other uses in the first table are planned. Each source is off until you switch it on, see [Configuration](#configuration). If you switch on a source later, the collector writes its history from the time where your data begins.

## Usage

In the future, [HELIOS](https://github.com/solectrus/helios) will set up the collector in a SOLECTRUS installation. You will not have to do anything.

Until then, run the collector yourself next to your InfluxDB:

1. Make a file `.env`. Copy `.env.example`, set the `INFLUX_*` settings to your InfluxDB, and switch on the sources that you need. Inside the container, `localhost` is the container itself, so `INFLUX_HOST` needs the name or the IP address of the host that runs your InfluxDB.
2. Start the container:

   ```bash
   docker run -it --rm --env-file .env ghcr.io/solectrus/public-data-collector
   ```

### Demo

`compose.yml` is a demo. It starts a new, empty InfluxDB together with the collector, and the collector writes into this new InfluxDB. Do not use it with an InfluxDB that holds your data.

```bash
docker compose up
```

`INFLUX_USERNAME` and `INFLUX_PASSWORD` in `.env` set up the new InfluxDB. Its bucket holds no other data, so the collector writes the newest values and no history. The section [History](#history) explains why.

## Configuration

| Variable             | Default | Description                                                     |
| -------------------- | ------- | --------------------------------------------------------------- |
| `COUNTRY`            |         | Country code, for example `DE`, required                        |
| `INTERVAL`           | `3600`  | Seconds between two reads of the electricity values, minimum 60 |
| `INFLUX_HOST`        |         | Host of your InfluxDB, required                                 |
| `INFLUX_SCHEMA`      | `http`  | `http` or `https`                                               |
| `INFLUX_PORT`        | `8086`  | Port of your InfluxDB                                           |
| `INFLUX_TOKEN`       |         | Token with read and write permission, required                  |
| `INFLUX_ORG`         |         | Organization in your InfluxDB, required                         |
| `INFLUX_BUCKET`      |         | Bucket in your InfluxDB, required                               |
| `TZ`                 | `UTC`   | Timezone, for example `Europe/Berlin`                           |
| `ENABLE_FUEL`        | `false` | `true` reads the fuel prices from the EU Weekly Oil Bulletin    |
| `ENABLE_GAS`         | `false` | `true` reads the gas price from Eurostat                        |
| `ENABLE_PUBLIC_GRID` | `false` | `true` reads the electricity values from Energy-Charts          |
| `BIDDING_ZONE`       |         | Only for Denmark, Italy, Norway and Sweden, see below           |

At least one source must be on. Otherwise, the collector stops with an error. Switch on only the sources whose values SOLECTRUS uses. Each source that is on downloads data on its schedule, and Energy-Charts does so every hour. For SOLECTRUS v1.4 (beta), this is `ENABLE_FUEL`.

The collector needs no other settings. If `ENABLE_PUBLIC_GRID` is `true`, it finds the bidding zone of the electricity price from `COUNTRY`. Denmark, Italy, Norway and Sweden have more than one zone, so set `BIDDING_ZONE` there, for example to `SE3`. The [page of Energy-Charts](lib/providers/energy_charts/README.md#configuration) tells how to find your zone.

## Operation

At each start, the collector reads every source that is on. After that, it reads the electricity values every `INTERVAL` seconds. It reads the gas and fuel prices on Friday at 06:00 in the timezone that `TZ` sets, because they change once a week or less.

If a source has no value for your country, or does not answer, the log shows an error, and the other values continue. The collector tries again later, and less often after each further error.

## History

The collector also writes the past values of each source. For Germany, the fuel prices go back to 2005, the gas price to 2007, the renewable share and the CO2 intensity to 2015, and the day-ahead price to 2018.

The collector writes this history only from the time where the other data in your bucket begins. Older points would make InfluxDB use more memory, and they would hold nothing to compare with.

For this, the token needs read permission for the bucket. Without it, the collector writes the newest values alone. If you import older data into the bucket later, restart the collector to fill the history.

The history of the electricity values is large. If `ENABLE_PUBLIC_GRID` is `true` and your data begins in 2020, the first start downloads about 260 MB and takes several minutes. A later start reads only the days that are missing.

## Development

[DEVELOPMENT.md](DEVELOPMENT.md) describes how the collector works inside and how to add a source.

## License

Copyright (c) 2026 Georg Ledermann, released under the MIT License
