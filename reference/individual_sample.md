# Individual-level synthetic sample data

A synthetically generated dataset of 200 individual records for use as
sample input in the DataGangeR Shiny app. Contains demographic and
health variables with realistic distributions. Generated with
`set.seed(42)`.

## Usage

``` r
individual_sample
```

## Format

A data frame with 200 rows and 7 columns:

- id:

  Integer record identifier

- age:

  Age in years (18–85)

- sex:

  Sex (Male / Female / Other)

- income:

  Annual income in dollars (log-normal, some NAs)

- education:

  Highest education level

- smoker:

  Logical smoking status

- bmi:

  Body mass index

## Source

Synthetically generated via `data-raw/individual_sample.R`
