# Geographic synthetic sample data

A synthetically generated dataset of 50 regional summary records for use
as sample input in the DataGangeR Shiny app. Simulates public-health
surveillance data aggregated by region. Generated with `set.seed(42)`.

## Usage

``` r
geographic_sample
```

## Format

A data frame with 50 rows and 5 columns:

- region:

  Region identifier (Region_01 through Region_50)

- population:

  Regional population count

- rate_per_100k:

  Event rate per 100,000 population

- category:

  Area classification (Urban / Suburban / Rural)

- risk_level:

  Assigned risk level (Low / Medium / High)

## Source

Synthetically generated via `data-raw/Geographic_sample.R`
