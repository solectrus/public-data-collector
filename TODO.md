# TODO

The code works: the tests pass and the collector boots. Everything below is about the release, the reach and possible extensions.

## Before the first release

- [ ] Switch the repository to public. A private repository hides the badges, blocks a branch protection rule, and blocks auto-merge.
- [ ] Make the package `public-data-collector` on GHCR public. Its visibility does not follow the repository. Without this, `docker pull` needs a login.
- [ ] Set the default permission of the workflow token to read in the settings of the repository. `push.yml` sets its own permissions and needs no change.
- [ ] Protect `develop` with the status check `test`, as `forecast-collector` does. A protection rule needs a public repository or GitHub Pro.
- [ ] Create `main` from `develop` for the first release. A version tag sets the `latest` tag of the image. Until then, the image has the tag `develop` alone, and `compose.yml` finds no image.
- [ ] Add `.github/workflows/automerge.yml` from `forecast-collector`, once the repository is public. A private repository cannot auto-merge, so the workflow is not part of this repository yet. The workflow reads the secret `PAT`.
- [ ] Cut the first version with the `/solectrus:release` skill. The git tag is the version, so nothing in the source needs a change.

## README badges

The README has the badge for the CI workflow. Three badges are missing. Copy their shape from `README.md` of `forecast-collector`:

- [ ] wakatime badge. It needs the ID of the project from wakatime.
- [ ] qlty maintainability badge. It needs the repository in qlty.
- [ ] qlty coverage badge. It also needs the step `qltysh/qlty-action/coverage` in `push.yml` and the secret `QLTY_COVERAGE_TOKEN`, as `forecast-collector` has them.

## Reach

- [ ] Add the service to the `helios` repository, so a user can switch it on there. The repositories `hosting` and `configurator` are archived, and `helios` replaces them. A service lives in `app/models/docker_images.rb`, in `app/services/compose/service_collection.rb` and in `app/services/export/services/`. Copy the shape of `tibber_collector.rb`. The service needs `INFLUX_TOKEN_READWRITE`, as `power_splitter.rb` does, because it reads the start of the history at the start.
- [ ] Document the environment variables in the `website` repository, which serves https://docs.solectrus.de/. A service gets a folder under `src/content/docs/docs/referenz/`. That page is the source of truth for every `INFLUX_*` and service variable, not this README.
- [ ] Mention this collector in the README of `tibber-collector`. Name the difference: `tibber-collector` reports the price you pay, this collector reports the exchange price. The exchange price is no replacement for the SENEC Charger, because its ratio of the best price to the average price differs without the fixed charges, and it fails for negative prices.
- [ ] Show the other values in the `solectrus` dashboard. The dashboard reads `Fuel:price_petrol`, `Fuel:price_diesel` and `Fuel:price_lpg` already, for the comparison with a combustion car (`Sensor::Query::FuelPrices`). It reads nothing else that this collector writes: not the day-ahead price, the renewable share, the CO2 intensity, the gas price or heating oil. The unit `percent` exists already.

## Possible extensions

### Energy-Charts

The collector reads `/v2/price` and `/v2/signal`, and of the second one only the share. For the history, it also reads the series `renewable_share_of_load` of `/v2/public_power`. For Germany, it computes the CO2 intensity from `/v2/total_power`. The API offers more. Each endpoint below needs a decision about its field names before anybody writes code. The measurement is settled: everything goes to `PublicGrid`.

- [ ] `/v2/ren_share_forecast`: forecast of the renewable, solar and wind share. On 2026-10-30, `/v2/ren_share_forecast` answered with HTTP 500, as on 2026-09-19. The path without `/v2`, `/ren_share_forecast`, sent data. Test both again before you plan work on it.
- [ ] `/v2/public_power`: net electricity production per production type in MW. Many series, so this needs a rule about which series to write.
- [ ] `/v2/solar_share`: solar share of the load in percent, split into a measured series and a forecast series. It is a subset of the renewable share, and it costs one request per cycle.
- [ ] Use `PublicGrid:co2_intensity` in the dashboard instead of the static `CO2_EMISSION_FACTOR`, which is 401 g/kWh for every hour of the history. The collector writes the value for Germany alone. Another country keeps the static factor.

Note the rate limit. The API documentation says that the limit applies to each endpoint and each client IP, not to the whole API. Most endpoints accept 2 requests per minute with a burst of 4. `/v2/price` accepts 2 per minute with a burst of 2, and `/v2/signal` accepts 20 per minute. Under high load, the server can lower these limits. A third endpoint therefore needs no longer interval, because it has a limit of its own.

### Other sources

- [ ] District heating. Eurostat has no price for it. The German statistical office publishes an index, not a price per kWh.
- [ ] Wood pellets. No source without an account is known today.
