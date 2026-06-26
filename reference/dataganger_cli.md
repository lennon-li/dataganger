# DataGangeR command-line interface

Testable command-line entrypoint used by the installed `exec/dataganger`
shim.

## Usage

``` r
dataganger_cli(args = commandArgs(trailingOnly = TRUE), quit = FALSE)
```

## Arguments

- args:

  Character vector of trailing command-line arguments.

- quit:

  Logical. When `TRUE`, terminate the R process using the returned
  status code. Tests pass `FALSE` and assert the integer code.

## Value

Integer status code: `0` success, `1` processing error, `2` syntax
error.
