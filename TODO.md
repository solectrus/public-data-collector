# TODO

## Other repositories

- [ ] `solectrus`: Show the values of the public grid. Today `solectrus` reads only the fuel prices and the gas price, for the comparison with a car and a heat pump. It does not read the day-ahead price (`PublicGrid:price`) and the renewable share (`PublicGrid:renewable_share`).
- [ ] `solectrus`: Use `PublicGrid:co2_intensity` instead of the static `CO2_EMISSION_FACTOR` (401 g/kWh). The collector writes this value only for Germany, so other countries keep the static factor.

## Possible extensions

No usable source is known for these:

- [ ] District heating. Eurostat has no price. The German statistical office publishes only an index, not a price per kWh.
- [ ] Wood pellets. No source without an account is known.
