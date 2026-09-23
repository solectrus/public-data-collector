# TODO

The code works: the tests pass and the collector boots. Everything below is about the release, the reach and possible extensions.

## Before the first release

- [ ] Switch the repository to public. A private repository hides the badges, blocks a branch protection rule, and blocks auto-merge.
- [ ] Protect `develop` with the status check `test`, as `forecast-collector` does. A protection rule needs a public repository or GitHub Pro.
- [ ] Create `main` from `develop` for the first release. A version tag sets the `latest` tag of the image. Until then, the image has the tag `develop` alone, and `compose.yml` finds no image.
- [ ] Add `.github/workflows/automerge.yml` from `forecast-collector`, once the repository is public. A private repository cannot auto-merge, so the workflow is not part of this repository yet. The workflow reads the secret `PAT`.
- [ ] Cut the first version with the `/solectrus:release` skill. The git tag is the version, so nothing in the source needs a change.

## README badges

The README has the badge for the CI workflow. One badge is missing, because it needs an ID from the service:

- [ ] wakatime badge.

Copy the shape of the badges from `README.md` of `tibber-collector`.

## Reach

- [ ] Add the service to the `helios` repository, so a user can switch it on there. The `hosting` repository is archived, `helios` replaces it. A service lives in `app/models/docker_images.rb`, in `app/services/compose/service_collection.rb` and in `app/services/export/services/`. Copy the shape of `tibber_collector.rb`. The service needs `INFLUX_TOKEN_READWRITE`, as `power_splitter.rb` does, because it reads the start of the history at the start.
- [ ] Document the environment variables in the `website` repository, which serves https://docs.solectrus.de/. A service gets a folder under `src/content/docs/docs/referenz/`. That page is the source of truth for every `INFLUX_*` and service variable, not this README.
- [ ] Say in the README of `tibber-collector` that this collector is an alternative without an account. Name the difference: `tibber-collector` reports the price you pay, this collector reports the exchange price.
- [ ] Add sensor definitions in the `solectrus` dashboard for the renewable share and the fossil prices. Without them the collector fills InfluxDB and nothing shows it. The unit `percent` exists already.

## Possible extensions

### Energy-Charts

The collector reads `/v2/price` and `/v2/signal`, and of the second one only the share. The API offers more. Each endpoint below needs a decision about its field names before anybody writes code. The measurement is settled: everything goes to `PUBLIC_GRID_MEASUREMENT`.

- [ ] `/v2/ren_share_forecast`: forecast of the renewable, solar and wind share. The endpoint answered with HTTP 500 on 2026-09-19. Test it again before you plan work on it.
- [ ] `/v2/public_power`: net electricity production per production type in MW. Many series, so this needs a rule about which series to write.
- [ ] `/v2/solar_share`: solar share of the load in percent, split into a measured series and a forecast series. It is a subset of the renewable share, and it costs one request per cycle.
- [ ] Decide whether the renewable share can replace the static `CO2_EMISSION_FACTOR` of the dashboard, which is 401 g/kWh for every hour of the history. A time-dependent factor needs a mapping from the share to g/kWh, and that mapping is a model, not a number the API reports.

Note the rate limit: the price endpoint accepts 2 requests per minute. One cycle makes one request to `/v2/price` and one to `/v2/signal`. It is not known whether the limit applies to each endpoint or to the whole API. Find this out before you add a third endpoint. If the limit applies to the whole API, a third endpoint needs a minimum interval above 60 seconds.

### Other sources

- [ ] District heating. Eurostat has no price for it. The German statistical office publishes an index, not a price per kWh.
- [ ] Wood pellets. No source without an account is known today.
