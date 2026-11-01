# TODO

## Other repositories

- [ ] `helios`: Add the service. Copy the shape of `tibber_collector.rb` in `app/models/docker_images.rb`, `app/services/compose/service_collection.rb` and `app/services/export/services/`. Use `INFLUX_TOKEN_READWRITE`, as `power_splitter.rb` does. Set up the service only when an electric car is configured, with `ENABLE_FUEL=true`.
- [ ] `solectrus`: Show more values in the dashboard. Today `Sensor::Query::FuelPrices` reads only `Fuel:price_petrol`, `Fuel:price_diesel` and `Fuel:price_lpg`. The day-ahead price, the renewable share, the CO2 intensity, the gas price and heating oil are not used.
- [ ] `solectrus`: Use `PublicGrid:co2_intensity` instead of the static `CO2_EMISSION_FACTOR` (401 g/kWh). The collector writes this value only for Germany, so other countries keep the static factor.

## Possible extensions

No usable source is known for these:

- [ ] District heating. Eurostat has no price. The German statistical office publishes only an index, not a price per kWh.
- [ ] Wood pellets. No source without an account is known.
