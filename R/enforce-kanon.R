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
#' @param max_suppress_frac Feasibility backstop. If satisfying `k` over the
#'   quasi-identifier set would require blanking more than this fraction of
#'   rows, k-anonymity is treated as infeasible for the chosen QI set: the
#'   coarsening/suppression is *not* applied (it would destroy the dataset),
#'   the synthetic output is returned populated, and a warning advises
#'   narrowing the quasi-identifiers or lowering `k`. Default 0.2.
#'
#' @return The shaped `synthetic` data frame, with an attribute `kanon`
#'   recording the achieved state (`smallest_cell`, `suppressed_cells`,
#'   `qi_cols`, `k`, `infeasible`).
#' @export
enforce_kanon <- function(synthetic, roles, k = 5, max_steps = 6L,
                          max_suppress_frac = 0.2) {
  if (is.null(roles) || !"disclosure_role" %in% names(roles)) {
    attr(synthetic, "kanon") <- list(
      qi_cols = character(0), k = k, smallest_cell = NA_integer_,
      suppressed_cells = 0L
    )
    return(synthetic)
  }

  dr <- stats::setNames(roles$disclosure_role, roles$variable)

  direct <- names(dr)[dr %in% "direct"]  # %in% is NA-safe; == returns NA for unselected roles
  drop_cols <- intersect(direct, names(synthetic))
  if (length(drop_cols)) {
    synthetic <- synthetic[, !names(synthetic) %in% drop_cols, drop = FALSE]
  }

  qi_cols <- intersect(dg_kanon_columns(roles), names(synthetic))
  if (length(qi_cols) == 0L) {
    attr(synthetic, "kanon") <- list(
      qi_cols = qi_cols, k = k, smallest_cell = NA_integer_,
      suppressed_cells = 0L, infeasible = FALSE
    )
    return(synthetic)
  }

  # Coarsen on a working copy so the populated original can be restored if the
  # k-anonymity target turns out to be infeasible for this QI set.
  base <- synthetic
  for (step in seq_len(max_steps)) {
    res <- assess_kanonymity(synthetic, qi_cols, k)
    if (is.na(res$smallest_cell) || res$smallest_cell >= k) {
      break
    }
    for (col in qi_cols) {
      synthetic[[col]] <- coarsen_qi_step(synthetic[[col]], step)
    }
  }

  # Feasibility backstop. If reaching k would blank more than `max_suppress_frac`
  # of rows, the QI set is too wide to anonymise without destroying the data
  # (e.g. 9 quasi-identifiers over a few hundred rows). Rather than ship a
  # mostly-NA dataset, back off entirely: return the populated (uncoarsened)
  # synthetic and tell the user how to make enforcement feasible.
  res <- assess_kanonymity(synthetic, qi_cols, k)
  n_rows <- nrow(synthetic)
  would_suppress <- if (!is.na(res$smallest_cell) && res$smallest_cell < k) {
    key <- kanon_key(synthetic, qi_cols)
    counts <- table(key)
    sum(as.integer(counts[key]) < k)
  } else {
    0L
  }
  if (n_rows > 0L && would_suppress / n_rows > max_suppress_frac) {
    cli::cli_warn(c(
      "k-anonymity (k = {k}) is infeasible over {length(qi_cols)} \\
       quasi-identifier{?s} without blanking most of the data; \\
       enforcement was skipped to preserve the synthetic output.",
      "i" = "Reaching k would suppress {would_suppress}/{n_rows} rows \\
             ({round(100 * would_suppress / n_rows)}%).",
      "i" = "Narrow the quasi-identifiers (mark measures/counts as \\
             {.val none}) or lower k, then re-synthesise."
    ))
    attr(base, "kanon") <- list(
      qi_cols = qi_cols, k = k, smallest_cell = res$smallest_cell,
      suppressed_cells = 0L, infeasible = TRUE
    )
    return(base)
  }

  suppressed <- 0L
  if (!is.na(res$smallest_cell) && res$smallest_cell < k) {
    key <- kanon_key(synthetic, qi_cols)
    counts <- table(key)
    small <- as.integer(counts[key]) < k
    suppressed <- length(unique(key[small]))
    for (col in qi_cols) {
      synthetic[[col]][small] <- NA
    }
  }

  # The NA bucket created by blanking may itself be smaller than k.
  # Absorb rows from the smallest remaining non-NA cell until the bucket reaches k.
  repeat {
    na_rows <- rowSums(is.na(synthetic[qi_cols])) == length(qi_cols)
    na_count <- sum(na_rows)
    if (na_count == 0L || na_count >= k) break
    non_na <- which(!na_rows)
    if (!length(non_na)) break
    key_non_na <- kanon_key(synthetic[non_na, , drop = FALSE], qi_cols)
    counts_non_na <- table(key_non_na)
    smallest_key <- names(which.min(counts_non_na))
    to_blank <- non_na[key_non_na == smallest_key]
    for (col in qi_cols) synthetic[[col]][to_blank] <- NA
    suppressed <- suppressed + 1L
  }

  final <- assess_kanonymity(synthetic, qi_cols, k)
  attr(synthetic, "kanon") <- list(
    qi_cols = qi_cols,
    k = k,
    smallest_cell = final$smallest_cell,
    suppressed_cells = suppressed,
    infeasible = FALSE
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
    # ISO date strings (YYYY-MM-DD) -- coarsen as Date to avoid 366-level
    # merge_rarest_level loop that leaves every row unique after 6 steps.
    chr_nna <- chr[!is.na(chr) & nzchar(trimws(chr))]
    if (length(chr_nna) > 0L &&
        mean(grepl("^\\d{4}-\\d{2}-\\d{2}$", trimws(chr_nna))) >= 0.9) {
      dates <- suppressWarnings(as.Date(chr, format = "%Y-%m-%d"))
      if (sum(!is.na(dates)) > 0L) {
        return(switch(min(step, 3L),
          coarsen_to_month(dates),
          coarsen_to_quarter(dates),
          coarsen_to_year(dates)
        ))
      }
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
