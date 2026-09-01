# Define bounded generation request limits

Creates the approved ranges for seeds, output rows, and development
datasets used by a frozen generator contract.

## Usage

``` r
generation_limits(
  n = c(1L, .Machine$integer.max),
  datasets = c(1L, 1L),
  seed = c(0L, .Machine$integer.max)
)
```

## Arguments

- n:

  Integer range of permitted output row counts.

- datasets:

  Integer range of permitted development dataset counts.

- seed:

  Integer range of permitted base seeds.

## Value

An S3 object of class `dataganger_generation_limits`.
