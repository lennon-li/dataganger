# Generate one or more approved synthetic datasets

Generates one independent development variation for each requested
dataset count. One dataset is returned directly; multiple datasets are
returned as a `dataganger_batch` with deterministic seeds and audit
provenance.

## Usage

``` r
generate_synthetic(frozen, seed = NULL, n = NULL, datasets = 1L)
```

## Arguments

- frozen:

  An approved `dataganger_frozen_generator` handle.

- seed:

  Optional scalar base seed within the approved range.

- n:

  Optional output row count within the approved range.

- datasets:

  Optional number of development variations within the approved range.

## Value

A `dataganger_synthetic` data frame when `datasets = 1`, otherwise a
`dataganger_batch`.
