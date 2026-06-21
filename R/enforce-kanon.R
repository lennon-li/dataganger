#' Enforce k-anonymity on a synthetic dataset (output guarantee)
#'
#' Shapes the synthetic output so that no quasi-identifier combination appears
#' in fewer than `k` records. Direct identifiers are removed. Quasi-identifiers
#' are coarsened step-by-step and any residual cell still below `k` has its QI
#' values blanked (`NA`). Operates on the output only.
#'
#' @param synthetic A synthetic data frame.
#' @param roles A roles object/data frame with `variable` + `disclosure_role`.
#' @param k Minimum cell size (default 5).
#' @param max_steps Maximum coarsening iterations (default 6).
#'
#' @return The shaped `synthetic` data frame, with an attribute `kanon`
#'   recording the achieved state (`smallest_cell`, `suppressed_cells`,
#'   `qi_cols`, `k`).
#' @export
enforce_kanon <- function(synthetic, roles, k = 5, max_steps = 6L) {
  if (is.null(roles) || !"disclosure_role" %in% names(roles)) {
    attr(synthetic, "kanon") <- list(
      qi_cols = character(0), k = k, smallest_cell = NA_integer_,
      suppressed_cells = 0L
    )
    return(synthetic)
  }

  dr <- stats::setNames(roles$disclosure_role, roles$variable)

  direct <- names(dr)[dr == "direct"]
  drop_cols <- intersect(direct, names(synthetic))
  if (length(drop_cols)) {
    synthetic <- synthetic[, !names(synthetic) %in% drop_cols, drop = FALSE]
  }

  qi_cols <- intersect(names(dr)[dr == "quasi"], names(synthetic))
  if (length(qi_cols) == 0L) {
    attr(synthetic, "kanon") <- list(
      qi_cols = qi_cols, k = k, smallest_cell = NA_integer_, suppressed_cells = 0L
    )
    return(synthetic)
  }

  for (step in seq_len(max_steps)) {
    res <- assess_kanonymity(synthetic, qi_cols, k)
    if (is.na(res$smallest_cell) || res$smallest_cell >= k) {
      break
    }
    for (col in qi_cols) {
      synthetic[[col]] <- coarsen_qi_step(synthetic[[col]], step)
    }
  }

  suppressed <- 0L
  res <- assess_kanonymity(synthetic, qi_cols, k)
  if (!is.na(res$smallest_cell) && res$smallest_cell < k) {
    key <- kanon_key(synthetic, qi_cols)
    counts <- table(key)
    small <- as.integer(counts[key]) < k
    suppressed <- length(unique(key[small]))
    for (col in qi_cols) {
      synthetic[[col]][small] <- NA
    }
  }

  final <- assess_kanonymity(synthetic, qi_cols, k)
  attr(synthetic, "kanon") <- list(
    qi_cols = qi_cols,
    k = k,
    smallest_cell = final$smallest_cell,
    suppressed_cells = suppressed
  )
  synthetic
}

kanon_key <- function(data, qi_cols) {
  parts <- lapply(data[qi_cols], function(col) {
    col <- as.character(col)
    col[is.na(col)] <- "<NA>"
    col
  })
  do.call(paste, c(parts, sep = "\u0001"))
}

coarsen_qi_step <- function(x, step) {
  if (inherits(x, "Date")) {
    return(switch(
      min(step, 3L),
      coarsen_to_month(x),
      coarsen_to_quarter(x),
      coarsen_to_year(x)
    ))
  }
  if (inherits(x, "POSIXct")) {
    return(as.Date(x))
  }
  if (is.character(x) || is.factor(x)) {
    chr <- as.character(x)
    if (is_geography_like(chr)) {
      return(coarsen_geography(chr, level = step))
    }
    return(merge_rarest_level(chr))
  }
  if (is.numeric(x)) {
    bins <- max(2L, 8L - step)
    br <- stats::quantile(
      x,
      probs = seq(0, 1, length.out = bins + 1L),
      na.rm = TRUE,
      names = FALSE
    )
    br <- unique(br)
    if (length(br) < 2L) {
      return(x)
    }
    return(as.character(cut(x, breaks = br, include.lowest = TRUE)))
  }
  x
}

merge_rarest_level <- function(chr) {
  tab <- sort(table(chr[!is.na(chr)]))
  if (length(tab) <= 1L) {
    return(chr)
  }
  rarest <- names(tab)[1]
  chr[!is.na(chr) & chr == rarest] <- "(other)"
  chr
}

is_geography_like <- function(chr) {
  vals <- chr[!is.na(chr) & nzchar(chr)]
  if (!length(vals)) {
    return(FALSE)
  }

  normalized <- gsub("\\s+", "", vals)
  all(grepl("^[0-9]{5}(-[0-9]{4})?$", vals) |
        grepl("^[A-Za-z][0-9][A-Za-z][0-9][A-Za-z][0-9]$", normalized))
}
