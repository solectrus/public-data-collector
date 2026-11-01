# EU Weekly Oil Bulletin

The collector reads the prices of petrol, diesel, heating oil and LPG from the [Weekly Oil Bulletin](https://energy.ec.europa.eu/data-and-analysis/weekly-oil-bulletin_en) of the European Commission. With them, you can compare the cost of an electric car with a combustion car, or of a heat pump with an oil heating.

The European Commission collects the consumer prices of petroleum products from every member state and publishes them once a week. The bulletin needs no account and no key.

## What the collector writes

| Measurement | Field               | Value             | Unit  | One value per |
| ----------- | ------------------- | ----------------- | ----- | ------------- |
| `Fuel`      | `price_petrol`      | Petrol price      | EUR/l | week          |
| `Fuel`      | `price_diesel`      | Diesel price      | EUR/l | week          |
| `Fuel`      | `price_heating_oil` | Heating oil price | EUR/l | week          |
| `Fuel`      | `price_lpg`         | LPG price         | EUR/l | week          |

The names are fixed. If a country does not report a product, that product gets no value for the week.

## The values

The prices are national averages with every tax included. They tell what a year of driving or heating costs. They do not tell where to fill up today.

The bulletin reports one petrol, Euro-super 95, and does not name the ethanol content. For Germany, the value follows Super E5, not E10. On 14 September 2026, E10 was about 9 cents per litre cheaper. Other member states can report a different grade under the same name.

## Configuration

Set `ENABLE_FUEL` to `true` to switch on the fuel prices. The collector uses the general setting `COUNTRY`. Countries outside the European Union are not in the bulletin. For such a country, the log shows an error for the fuel prices, and the other values continue.

## When the collector reads

The collector reads at each start, and then on Friday at 06:00 in the timezone that `TZ` sets. The European Commission surveys the prices of every Monday. It publishes them on the Wednesday or Thursday after. A read on Friday therefore finds the newest week, with a margin for a late publication. Each read downloads a file of about 4 MB.

At the first start, the collector also writes the history from the time where the other data in your bucket begins. The [README of the collector](../../../README.md#history) explains why. The prices go back to 2005.

Every later read writes the last eight weeks again. A correction of an older week arrives with the next start.

If the European Commission changes the page of the bulletin, the collector can fail to find the file. The log then shows an error. The prices in InfluxDB stay, and the next read that finds the file fills the missing weeks.

## License

The prices come from the [Weekly Oil Bulletin](https://energy.ec.europa.eu/data-and-analysis/weekly-oil-bulletin_en) of the European Commission. The file states that reproduction is authorised when the source is named.
