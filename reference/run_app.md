# Launch the DataGangeR Shiny Application

Opens the DataGangeR interactive workflow in a local Shiny app. Requires
the `shiny`, `bslib`, `DT`, and `plotly` packages.

## Usage

``` r
run_app(max_upload_mb = 50, launch = interactive(), port = NULL, ...)
```

## Arguments

- max_upload_mb:

  Maximum file upload size in megabytes. Default 50.

- launch:

  Whether to launch the app. Default
  [`interactive()`](https://rdrr.io/r/base/interactive.html). Set to
  `FALSE` to configure options without blocking (useful for testing).

- port:

  Port to pass to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).
  Default `NULL`.

- ...:

  Additional arguments passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

## Value

Invisibly `NULL`.

## Examples

``` r
if (interactive()) {
  run_app()
}
```
