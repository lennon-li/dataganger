#' Render the Quarto analysis-report template for a synthetic dataset
#'
#' Builds a self-contained `.qmd` (Quarto) document the user can render locally
#' to read both their original and synthetic data and compare them: summary
#' statistics, per-variable distribution plots (green = original, magenta =
#' synthetic), and DataGangeR's built-in fidelity/privacy comparison. The
#' numeric and categorical column lists are derived from `synthetic` so the
#' generated code targets the actual columns.
#'
#' @param synthetic A synthetic data frame (its column types drive which
#'   variables are plotted as numeric vs categorical).
#' @param spec Optional recorded synthesis specification. When `NULL`, uses
#'   `attr(synthetic, "spec")`.
#' @param roles Optional recorded role decisions used to rebuild the exact
#'   reproduction pipeline.
#' @param purpose Optional purpose label, used for a one-line note at the top.
#'
#' @return A single character string: the contents of the `.qmd` file.
#' @keywords internal
#' @noRd
render_analysis_template <- function(synthetic, spec = NULL, roles = NULL, purpose = NULL) {
  if (!is.data.frame(synthetic)) {
    cli::cli_abort("{.arg synthetic} must be a data frame")
  }

  spec <- spec %||% attr(synthetic, "spec", exact = TRUE)

  template <- paste(
    readLines(
      system.file("templates", "analysis_template.qmd", package = "dataganger"),
      warn = FALSE
    ),
    collapse = "\n"
  )

  is_num <- vapply(synthetic, is.numeric, logical(1))
  numeric_cols     <- names(synthetic)[is_num]
  categorical_cols <- names(synthetic)[!is_num]

  purpose_line <- if (!is.null(purpose) && length(purpose) == 1L && nzchar(purpose)) {
    sprintf("Synthetic data generated for the **%s** objective.", purpose)
  } else {
    ""
  }

  interpolate(
    template,
    purpose_line = purpose_line,
    reproduction_script = build_reproduction_script(
      spec = spec,
      roles = roles,
      purpose = purpose %||% spec$purpose %||% "unspecified"
    ),
    numeric_cols = r_char_vector(numeric_cols),
    categorical_cols = r_char_vector(categorical_cols)
  )
}

#' Render a character vector as R source code, e.g. `c("a", "b")`
#' @keywords internal
#' @noRd
r_char_vector <- function(x) {
  if (length(x) == 0L) {
    return("character(0)")
  }
  paste0("c(", paste(sprintf('"%s"', escape_r_string(x)), collapse = ", "), ")")
}
