#' Assess k-anonymity over a set of quasi-identifier columns
#'
#' Cross-tabulates the quasi-identifier columns and reports how many records
#' fall in combinations (equivalence classes) smaller than `k`. `NA` is treated
#' as a distinct level so that missing values cannot mask a small cell.
#'
#' @param data A data frame.
#' @param qi_cols Character vector of quasi-identifier column names.
#' @param k Minimum acceptable cell size (default 5).
#'
#' @return A list with `no_qi` (logical), `smallest_cell` (integer),
#'   `n_below`, `pct_below`, and `worst_cells` (a tibble of the smallest
#'   combinations and their counts).
#' @export
assess_kanonymity <- function(data, qi_cols, k = 5) {
  qi_cols <- intersect(qi_cols, names(data))
  n <- nrow(data)

  if (length(qi_cols) == 0L || n == 0L) {
    return(list(
      no_qi = length(qi_cols) == 0L,
      smallest_cell = NA_integer_,
      n_below = 0L,
      pct_below = 0,
      worst_cells = tibble::tibble()
    ))
  }

  key_df <- lapply(data[qi_cols], function(col) {
    col <- as.character(col)
    col[is.na(col)] <- "<NA>"
    col
  })
  key <- do.call(paste, c(key_df, sep = "\u0001"))
  counts <- table(key)
  cell_n <- as.integer(counts[key])

  below <- cell_n < k
  smallest <- as.integer(min(cell_n))

  uniq <- !duplicated(key)
  worst <- tibble::as_tibble(data[uniq, qi_cols, drop = FALSE])
  worst$n <- as.integer(counts[key[uniq]])
  worst <- worst[order(worst$n), , drop = FALSE]
  worst <- worst[worst$n < k, , drop = FALSE]
  worst <- utils::head(worst, 10L)

  list(
    no_qi = FALSE,
    smallest_cell = smallest,
    n_below = as.integer(sum(below)),
    pct_below = round(100 * sum(below) / n, 1),
    worst_cells = worst
  )
}
