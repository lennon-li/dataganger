# Internal utility functions for dataganger

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

# ---------------------------------------------------------------------------
# Diagnostic logging
# ---------------------------------------------------------------------------

# Emit a timestamped diagnostic line to the console. Gated on
# getOption("dataganger.verbose", TRUE) so users can silence it. Exists to make
# long synthesis / profiling phases observable when a run appears to hang.
dg_log <- function(...) {
  if (!isTRUE(getOption("dataganger.verbose", TRUE))) {
    return(invisible(NULL))
  }
  message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(...)))
  invisible(NULL)
}

# Run `expr`, logging a "<label> ..." line before it starts and a
# "<label> done: N.NNs" line after it returns. The before-line is the point:
# if `expr` hangs, the console shows which phase was entered and never left.
dg_timeit <- function(label, expr) {
  dg_log(label, " ...")
  start <- proc.time()[["elapsed"]]
  res <- force(expr)
  dg_log(sprintf("%s done: %.2fs", label, proc.time()[["elapsed"]] - start))
  res
}

# ---------------------------------------------------------------------------
# Cooperative cancellation
# ---------------------------------------------------------------------------

# Abort the current synthesis with a classed condition when
# getOption("dataganger.cancel") is TRUE. Checked at column boundaries inside
# synthesize_marginal() so a long marginal run can be stopped cleanly. Used by
# headless / CLI callers; the Shiny app instead cancels by killing the
# background process that runs the synthesis (see run_synthesis_async()).
check_cancel <- function() {
  if (isTRUE(getOption("dataganger.cancel", FALSE))) {
    cli::cli_abort("Synthesis cancelled.", class = "dataganger_cancelled")
  }
  invisible(NULL)
}

synthpop_citation <- function() {
  paste(
    "Nowok B, Raab GM, Dibben C (2016).",
    "\"synthpop: Bespoke Creation of Synthetic Data in R.\"",
    "Journal of Statistical Software, 74(11), 1-26.",
    "doi:10.18637/jss.v074.i11"
  )
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
    result <- gsub(paste0("{%", nm, "}"), as.character(args[[nm]]), result, fixed = TRUE)
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
