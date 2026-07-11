# Synthesize a data double

Creates a synthetic copy of a dataset using the specified specification
and engine. The internal engine supports schema-only (Level 1) and
marginal (Level 2) synthesis. The optional synthpop engine is used for
objectives that request moderate or high relationship preservation.

## Usage

``` r
synthesize_data(data, spec, roles = NULL, engine = NULL)
```

## Arguments

- data:

  A data frame to synthesize from.

- spec:

  A `dataganger_spec` object from
  [`synth_spec()`](https://dataganger.biostats.ai/reference/synth_spec.md).

- roles:

  Optional; a `dataganger_roles` object from
  [`detect_roles()`](https://dataganger.biostats.ai/reference/detect_roles.md).
  Informs column treatment but does not override the spec.

- engine:

  Character or `NULL`. Engine to use: `"auto"`, `"internal"`,
  `"marginal"` (alias for `"internal"`), or `"synthpop"`. When `NULL`,
  defaults to `spec$engine` or derives from
  `spec$preserve_correlations`.

## Value

An S3 object of class `dataganger_synthetic`, a tibble with attributes
`spec`, `original_dims`, `seed_used`, and `generated_at`.

## Disabling synthpop

Set `options(dataganger.disable_synthpop = TRUE)` to steer auto-derived
synthesis onto the internal engine even when synthpop is installed. This
is intended for environments where a synthpop synthesis is undesirable
or can hang unattended (for example continuous integration). An explicit
`engine = "synthpop"` request is still honoured; only objective-derived
routing is affected.

## Examples

``` r
dat <- data.frame(x = 1:5, y = letters[1:5])
spec <- synth_spec(purpose = "demo")
syn <- synthesize_data(dat, spec)
```
