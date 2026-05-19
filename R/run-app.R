#' Launch the DataGangeR Shiny Application
#'
#' Opens the DataGangeR interactive workflow in a local Shiny app. Requires
#' the `shiny` and `DT` packages (listed in `Suggests`).
#'
#' @param max_upload_mb Maximum file upload size in megabytes. Default 50.
#' @param ... Reserved for future arguments.
#'
#' @return Invisibly `NULL`.
#' @export
#'
#' @examples
#' if (interactive()) {
#'   run_app()
#' }
run_app <- function(max_upload_mb = 50, ...) {
  rlang::check_installed(
    c("shiny", "bslib", "DT"),
    reason = "to run the DataGangeR Shiny app"
  )
  options(shiny.maxRequestSize = max_upload_mb * 1024^2)
  shiny::runApp(
    appDir = system.file("app", package = "dataganger"),
    display.mode = "normal"
  )
}
