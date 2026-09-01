# Freeze a supported synthesis policy for repeated generation

Fits the dependency-free internal generator while the source data are in
a human-controlled session, writes the fitted state to a private store,
and returns a source-free handle containing the public contract and
opaque references. The fitted state is not included in the returned
object.

## Usage

``` r
freeze_synthesis(
  data,
  spec,
  roles = NULL,
  allowed = generation_limits(),
  store = NULL
)
```

## Arguments

- data:

  A data frame to use during the one-time fitting operation.

- spec:

  A `dataganger_spec` created by
  [`synth_spec()`](https://dataganger.biostats.ai/reference/synth_spec.md)
  with `engine = "internal"`.

- roles:

  A `dataganger_roles` object. If `NULL`, roles are detected from `data`
  before fitting.

- allowed:

  A `dataganger_generation_limits` object defining permitted seed,
  row-count, and dataset-count ranges.

- store:

  A persistent private store path or an existing private store object.
  It must be supplied explicitly so the handle can be reopened in a
  later R session.

## Value

A `dataganger_frozen_generator` handle. Save this handle with
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) if it must be
reopened in a later R session.
