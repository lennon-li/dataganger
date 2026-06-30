# Report a problem or share feedback

Prints a pre-filled GitHub issue you can copy into your browser for the
`lennon-li/dataganger` repository, with package and R environment
details already populated. Use this to report a bug, suggest a feature,
or send general feedback without copying session details by hand.

## Usage

``` r
report_issue(
  message = NULL,
  context = NULL,
  type = c("feedback", "bug", "feature")
)
```

## Arguments

- message:

  Character. A short description of the problem or suggestion. If
  `NULL`, a placeholder prompt is used.

- context:

  Character. Optional context about where the issue happened, such as
  `"Shiny app"` or `"export_synthetic()"`.

- type:

  Character. One of `"feedback"`, `"bug"`, or `"feature"`.

## Value

Invisibly, the GitHub issue URL that was printed.

## Examples

``` r
if (interactive()) {
  report_issue(
    message = "The export step was unclear when I skipped the dictionary.",
    context = "Shiny app",
    type = "feedback"
  )
}
```
