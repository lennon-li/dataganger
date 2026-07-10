# Create a one-command agent-ready bundle from a raw data file

Reads a data file, profiles it, detects column roles, synthesizes data,
and exports a zip bundle suitable for passing to an AI agent.

## Usage

``` r
make_agent_bundle(
  file,
  out,
  purpose = "development",
  seed = NULL,
  overwrite = FALSE,
  ...
)
```

## Arguments

- file:

  Path to the input data file. Passed to
  [`read_input()`](https://lennon-li.github.io/dataganger/reference/read_input.md).

- out:

  Path for the output zip file.

- purpose:

  Synthesis purpose preset. Defaults to `"development"`. See
  [`synth_spec()`](https://lennon-li.github.io/dataganger/reference/synth_spec.md)
  for valid values.

- seed:

  Optional integer random seed for reproducible synthesis.

- overwrite:

  Logical. When `FALSE` (the default), aborts if `out` already exists.

- ...:

  Additional arguments passed to
  [`read_input()`](https://lennon-li.github.io/dataganger/reference/read_input.md)
  only (e.g. `encoding`, `sheet`).

## Value

Invisibly, the written bundle path.

## Examples

``` r
dat <- data.frame(
  age = c(24, 28, 35, 41),
  score = c(88, 91, 84, 95),
  grp = c("A", "A", "B", "B")
)
path <- tempfile(fileext = ".csv")
readr::write_csv(dat, path)
make_agent_bundle(
  file = path,
  out = tempfile(fileext = ".zip"),
  purpose = "demo",
  seed = 1
)
```
