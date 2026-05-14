# Schema-only synthesis (Level 1)
#
# Internal function. Returns a 0-row tibble with column names and types
# matching the original. No values are synthesized.
#
# Used by: safer_external preset, level = "schema"

synthesize_schema <- function(data, spec, roles = NULL) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame")
  }

  nms <- names(data)
  types <- lapply(data, function(col) {
    if (haven::is.labelled(col)) {
      haven::labelled(
        double(0),
        labels = attr(col, "labels", exact = TRUE),
        label  = attr(col, "label",  exact = TRUE)
      )
    } else if (inherits(col, "Date")) {
      as.Date(character(0))
    } else if (inherits(col, "POSIXct")) {
      as.POSIXct(character(0))
    } else if (is.factor(col)) {
      factor(character(0), levels = levels(col))
    } else if (is.numeric(col)) {
      numeric(0)
    } else if (is.character(col)) {
      character(0)
    } else if (is.logical(col)) {
      logical(0)
    } else {
      character(0)
    }
  })

  out <- tibble::as_tibble(stats::setNames(types, nms))
  out
}
