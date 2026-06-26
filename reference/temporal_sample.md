# Temporal synthetic sample data

A synthetically generated dataset of 365 daily records for use as sample
input in the DataGangeR Shiny app. Simulates environmental monitoring
data across multiple sites. Generated with `set.seed(42)`.

## Usage

``` r
temporal_sample
```

## Format

A data frame with 365 rows and 5 columns:

- date:

  Measurement date (daily from 2023-01-01)

- site_id:

  Site identifier (SITE_A through SITE_E)

- measurement:

  Numeric measurement value (some NAs)

- temperature:

  Ambient temperature in degrees Celsius

- flagged:

  Logical quality-control flag

## Source

Synthetically generated via `data-raw/temporal_sample.R`
