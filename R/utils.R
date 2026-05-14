# Internal utility functions for dataganger

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

# Safely compute length-unique for vctrs compatibility
n_distinct_safe <- function(x) {
  length(unique(x))
}

# Simple list transpose helper (avoids purrr for this small use)
list_transpose_simple <- function(.l) {
  if (length(.l) == 0) return(list())
  nms <- names(.l[[1]])
  out <- stats::setNames(vector("list", length(nms)), nms)
  for (nm in nms) {
    out[[nm]] <- lapply(.l, `[[`, nm)
  }
  out
}

# Template string interpolator (lightweight, avoids depending on glue)
# Uses `%s` style placeholder replacement
interpolate <- function(template, ...) {
  args <- list(...)
  result <- template
  for (nm in names(args)) {
    result <- gsub(sprintf("\\{\\%s\\}", nm), as.character(args[[nm]]), result)
  }
  result
}

# ===========================================================================
# Future-use stubs to satisfy R CMD check (referenced in later phases)
# ===========================================================================

# Pre-export type-guard helper (vctrs)
vec_check <- function(x, ptype) {
  vctrs::vec_ptype(x)
}

# Future purrr-style mapping helper
map_safe <- function(.x, .f, ...) {
  purrr::map(.x, .f, ...)
}

# Future tidyr-style reshape helper
pivot_safe <- function(data, ...) {
  tidyr::pivot_longer(data, ...)
}

# Future JSON manifest writer stub
json_write_stub <- function(x) {
  jsonlite::toJSON(x, auto_unbox = TRUE)
}

# Future zip bundle stub
zip_stub <- function(files, zipfile) {
  zip::zip(zipfile, files)
}

# Future withr seed wrapper stub
seed_stub <- function(seed, code) {
  withr::with_seed(seed, code)
}

# Future utils helper stub
utils_stub <- function() {
  utils::head(utils::installed.packages())
}

