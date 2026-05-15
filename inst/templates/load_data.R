load_dataganger_bundle <- function(path = ".") {
  csv_path <- file.path(path, "synthetic_data.csv")
  if (!file.exists(csv_path)) {
    stop("synthetic_data.csv not found in: ", path, call. = FALSE)
  }

  data <- readr::read_csv(
    csv_path,
    col_types = readr::cols(
{%schema_block}
    ),
    show_col_types = FALSE
  )

{%labelled_block}

  data
}
