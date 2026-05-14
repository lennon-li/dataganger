#' Read a data file into a tibble
#'
#' Reads CSV, Excel (`.xlsx`, `.xls`), SAS (`.sas7bdat`), and XPT (`.xpt`)
#' files into a tibble. Dispatches on file extension.
#'
#' @param file Path to the data file.
#' @param sheet For Excel files, the sheet name or index to read. Passed to
#'   [readxl::read_excel()]. Ignored for non-Excel formats.
#' @param ... Additional arguments passed to the underlying reader
#'   (`readr::read_csv()`, `readxl::read_excel()`, `haven::read_sas()`, or
#'   `haven::read_xpt()`).
#'
#' @return A [tibble::tibble()]. SAS/XPT imports preserve `haven_labelled`
#'   vectors as-is.
#' @export
#'
#' @examples
#' f <- system.file("extdata", package = "dataganger")
#' # read_input(file.path(f, "example.csv"))
read_input <- function(file, sheet = NULL, ...) {
  if (!file.exists(file)) {
    cli::cli_abort("File does not exist: {.path {file}}")
  }

  ext <- tolower(tools::file_ext(file))

  switch(ext,
    csv = {
      readr::read_csv(file, ..., show_col_types = FALSE)
    },
    xlsx = ,
    xls = {
      if (is.null(sheet)) {
        readxl::read_excel(file, ...)
      } else {
        readxl::read_excel(file, sheet = sheet, ...)
      }
    },
    sas7bdat = {
      haven::read_sas(file, ...)
    },
    xpt = {
      haven::read_xpt(file, ...)
    },
    {
      cli::cli_abort(c(
        "Unsupported file extension: {.val {ext}}",
        "i" = "Supported formats: {.val .csv}, {.val .xlsx}, {.val .xls}, {.val .sas7bdat}, {.val .xpt}"
      ))
    }
  )
}
