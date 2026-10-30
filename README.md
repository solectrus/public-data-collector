[![Continuous integration](https://github.com/solectrus/public-data-collector/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/public-data-collector/actions/workflows/push.yml)

# Public-data collector

The collector writes public prices and values into your InfluxDB. With them, you can compare the cost of a heat pump with a gas heating, or the cost of an electric car with a combustion car. You can also tell how much CO2 your grid import caused, and when the electricity from the grid is cheap or green.

The collector reads these values:

- Electricity: the day-ahead price, the renewable share and the CO2 intensity, every hour
- Natural gas: the price, every Friday
- Fuel: the prices of petrol, diesel, heating oil and LPG, every Friday

Every source is free and needs no account. The sources cover Europe. Each source has a page with the details of its values: [Energy-Charts](lib/providers/energy_charts/README.md) for electricity, [Eurostat](lib/providers/eurostat/README.md) for natural gas, and the [EU Weekly Oil Bulletin](lib/providers/oil_bulletin/README.md) for fuel.

## Usage

In the future, [HELIOS](https://github.com/solectrus/helios) will set up the collector in a SOLECTRUS installation. You will not have to do anything.

Until then, run the collector yourself next to your InfluxDB:

1. Make a file `.env`. Copy `.env.example`, and set the `INFLUX_*` settings to your InfluxDB. Inside the container, `localhost` is the container itself, so `INFLUX_HOST` needs the name or the IP address of the host that runs your InfluxDB.
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

| Variable        | Default | Description                                                     |
| --------------- | ------- | --------------------------------------------------------------- |
| `COUNTRY`       |         | Country code, for example `DE`, required                        |
| `INTERVAL`      | `3600`  | Seconds between two reads of the electricity values, minimum 60 |
| `INFLUX_HOST`   |         | Host of your InfluxDB, required                                 |
| `INFLUX_SCHEMA` | `http`  | `http` or `https`                                               |
| `INFLUX_PORT`   | `8086`  | Port of your InfluxDB                                           |
| `INFLUX_TOKEN`  |         | Token with read and write permission, required                  |
| `INFLUX_ORG`    |         | Organization in your InfluxDB, required                         |
| `INFLUX_BUCKET` |         | Bucket in your InfluxDB, required                               |
| `TZ`            | `UTC`   | Timezone, for example `Europe/Berlin`                           |
| `BIDDING_ZONE`  |         | Only for Denmark, Italy, Norway and Sweden, see below           |

The collector needs no other settings. It finds the bidding zone of the electricity price from `COUNTRY`. Denmark, Italy, Norway and Sweden have more than one zone, so set `BIDDING_ZONE` there, for example to `SE3`. The [page of Energy-Charts](lib/providers/energy_charts/README.md#configuration) tells how to find your zone.

## Operation

At each start, the collector reads every source at once. After that, it reads the electricity values every `INTERVAL` seconds. It reads the gas and fuel prices on Friday at 06:00 in the timezone that `TZ` sets, because they change once a week or less.

If a source has no value for your country, or does not answer, the log shows an error, and the other values continue. The collector tries again later, and less often after each further error.

## History

The collector also writes the past values of each source. For Germany, the fuel prices go back to 2005, the gas price to 2007, the renewable share and the CO2 intensity to 2015, and the day-ahead price to 2018.

The collector writes this history only from the time where the other data in your bucket begins. Older points would make InfluxDB use more memory, and they would hold nothing to compare with.

For this, the token needs read permission for the bucket. Without it, the collector writes the newest values alone. If you import older data into the bucket later, restart the collector to fill the history.

The history of the electricity values is large. If your data begins in 2020, the first start downloads about 260 MB and takes several minutes. A later start reads only the days that are missing.

## What the collector writes

| Measurement  | Field               | Value                       | Unit    |
| ------------ | ------------------- | --------------------------- | ------- |
| `PublicGrid` | `price`             | Day-ahead electricity price | EUR/kWh |
| `PublicGrid` | `renewable_share`   | Renewable share             | percent |
| `PublicGrid` | `co2_intensity`     | CO2 intensity               | g/kWh   |
| `Gas`        | `price`             | Natural gas price           | EUR/kWh |
| `Fuel`       | `price_petrol`      | Petrol price                | EUR/l   |
| `Fuel`       | `price_diesel`      | Diesel price                | EUR/l   |
| `Fuel`       | `price_heating_oil` | Heating oil price           | EUR/l   |
| `Fuel`       | `price_lpg`         | LPG price                   | EUR/l   |

The names are fixed, so SOLECTRUS finds the values without a configuration.

## Development

[DEVELOPMENT.md](DEVELOPMENT.md) describes how the collector works inside and how to add a source.

## License

Copyright (c) 2026 Georg Ledermann, released under the MIT License
