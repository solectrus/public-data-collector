# EU Weekly Oil Bulletin

This provider reads the prices of petrol, diesel, heating oil and LPG from the [Weekly Oil Bulletin](https://energy.ec.europa.eu/data-and-analysis/weekly-oil-bulletin_en) of the European Commission. With them, you can compare what driving and heating cost.

The European Commission collects the consumer prices of petroleum products from every member state and publishes them once a week. The file needs no account and no key.

## What the provider writes

| Sensor                   | Unit  | Pace |
| ------------------------ | ----- | ---- |
| `Fuel:price_petrol`      | EUR/l | week |
| `Fuel:price_diesel`      | EUR/l | week |
| `Fuel:price_heating_oil` | EUR/l | week |
| `Fuel:price_lpg`         | EUR/l | week |

The table shows the default names. You can rename the measurement. The field names are fixed.

A product that a country does not report gets no value for that week.

## Configuration

| Variable           | Default | Description                                    |
| ------------------ | ------- | ---------------------------------------------- |
| `FUEL_MEASUREMENT` | `Fuel`  | Measurement for the products sold by the litre |

The provider also needs the general setting `COUNTRY`. The bulletin writes Greece as `GR`, and the provider changes `EL` to `GR`.

Countries outside the European Union are not in the bulletin. For such a country, every read logs an error for the fuel prices, and the other values continue.

## How often the provider reads

The provider reads at the start, and then once a week on Friday at 06:00, whatever the interval is. The time is in the timezone that `TZ` sets. The read at the start fills InfluxDB at once for a new container.

The European Commission surveys the prices of every Monday. It saves the file on the Wednesday after, and announces it on the Thursday. A read on Friday therefore finds the newest week and keeps two days of margin for a late upload.

One read downloads about 4 MB. The file has no ETag and no Last-Modified header, so a conditional request is not possible and every read loads all of it. The server offers no compression. Compression also saves only 6 percent, because the file format is a ZIP archive.

If a read fails, the next read repairs the data.

## Petrol, diesel, heating oil and LPG

The prices are national averages with every tax included. They tell what a year of driving or heating costs. They do not tell where to fill up today, and this provider is not made for that question.

The file holds every week back to 2005. The first read after a start writes the weeks from the time where the other data in your bucket begins. The section [History](../../../README.md#history) explains why. Every later read writes the last eight weeks. If the Commission corrects an older week, the next start writes the correction.

The bulletin reports one petrol, Euro-super 95, and does not name the ethanol content. For Germany, the value follows Super E5, not E10. In the week of 14 September 2026, the bulletin gave 2.357 EUR per litre. On the same day, the national average was 2.36 EUR for E5 and about 2.27 EUR for E10. Other member states can report a different grade under the same name.

The bulletin also reports two heavy fuel oils. Those power ships and industry, and the provider leaves them out.

### How the provider finds the file

The bulletin is behind a link that carries a UUID. In 2026, the UUID stayed the same while the file changed every week, but the Commission does not promise that. The provider therefore reads the page of the bulletin and finds the link by its file name.

If the provider cannot read the page, or the page no longer names the file, the read fails and the log shows the error. The prices that are already in InfluxDB stay. The next read that finds the file fills the weeks that are missing.

## Data source

The prices come from the [Weekly Oil Bulletin](https://energy.ec.europa.eu/data-and-analysis/weekly-oil-bulletin_en) of the European Commission. The file states that reproduction is authorised when the source is named.

## Files

```
provider.rb            the provider: reads at the start and on Friday at 06:00
settings.rb            the settings, read from ENV
client.rb              finds the file on the page, downloads it and reads the weeks
xlsx.rb                reads one sheet of an XLSX file, row by row
fuel_price_series.rb   the prices per litre, one record per week
```

The unpacked sheet is about 9 MB. `xlsx.rb` therefore reads the XML one token at a time and never keeps the whole sheet in memory.

The specs replay the page from the recorded answer `spec/cassettes/oil_bulletin/page.yml`. To record it again, delete the file and run the specs.

The file is a 4 MB spreadsheet, which has no place in a repository. The specs therefore build their own file in the shape of the bulletin, with `spec/support/xlsx_builder.rb`.
