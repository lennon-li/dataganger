#' Launch the DataGangeR Shiny Application
#'
#' Opens the DataGangeR interactive workflow in a local Shiny app. Requires
#' the `shiny` and `DT` packages (listed in `Suggests`).
#'
#' @param ... Reserved for future arguments (e.g. `max_upload_mb`).
#'
#' @return Invisibly `NULL`.
#' @export
#'
#' @examples
#' if (interactive()) {
#'   run_app()
#' }
run_app <- function(...) {
  rlang::check_installed(
    c("shiny", "DT"),
    reason = "to run the DataGangeR Shiny app"
  )
  invisible(NULL)
}
