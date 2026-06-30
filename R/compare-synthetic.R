#' Compare original and synthetic datasets
#'
#' Compares an original dataset with its synthetic double across dataset-level
#' dimensions, numeric distributions, categorical distributions, and numeric
#' correlations. Returns a structured `dataganger_comparison` object.
#'
#' @param original The original data frame.
#' @param synthetic The synthetic data frame (from [synthesize_data()]).
#' @param roles Optional; a `dataganger_roles` object from [detect_roles()].
#'
#' @return An S3 object of class `dataganger_comparison`, a list with
#'   components `dataset`, `numeric`, `categorical`, `relationship`,
#'   `privacy_flags`, and `meta`.
#' @export
#'
#' @examples
#' dat <- data.frame(x = 1:10, y = letters[1:10])
#' spec <- synth_spec(purpose = "demo")
#' syn <- synthesize_data(dat, spec)
#' compare_synthetic(dat, syn)

#' Map a fidelity p-value to a colour band.
#'
#' Lower p = a more significant original-vs-synthetic difference = poorer
#' fidelity. `NA` means no inference was run (min/max) -> "none".
#' @keywords internal
#' @noRd
fidelity_color <- function(p) {
  if (length(p) != 1L || is.na(p)) return("none")
  if (p < 0.01) return("bad")
  if (p < 0.05) return("warn")
  "good"
}

compare_synthetic <- function(original, synthetic, roles = NULL) {
  if (!is.data.frame(original)) {
    cli::cli_abort("{.arg original} must be a data frame")
  }
  if (!is.data.frame(synthetic)) {
    cli::cli_abort("{.arg synthetic} must be a data frame")
  }

  # -- dataset-level --
  ds <- compare_dataset(original, synthetic)

  # -- numeric comparison --
  num_cmp <- compare_numeric(original, synthetic)

  # -- categorical comparison --
  cat_cmp <- compare_categorical(original, synthetic)

  # -- relationship (correlation) --
  rel_cmp <- compare_relationship(original, synthetic)

  out <- list(
    dataset       = ds,
    numeric       = num_cmp,
    categorical   = cat_cmp,
    relationship  = rel_cmp,
    privacy_flags = NULL,
    meta          = list(
      generated_at = Sys.time(),
      nrow_orig    = nrow(original),
      ncol_orig    = ncol(original),
      nrow_syn     = nrow(synthetic),
      ncol_syn     = ncol(synthetic)
    )
  )
  class(out) <- "dataganger_comparison"
  out
}

# ===========================================================================
# Dataset-level comparison
# ===========================================================================

compare_dataset <- function(orig, syn) {
  common_cols <- intersect(names(orig), names(syn))
  type_match <- vapply(common_cols, function(nm) {
    identical(class(orig[[nm]]), class(syn[[nm]]))
  }, logical(1))

  miss_orig <- sum(is.na(orig)) / (nrow(orig) * ncol(orig)) * 100
  miss_syn  <- sum(is.na(syn))  / (nrow(syn)  * ncol(syn))  * 100

  tibble::tibble(
    metric             = c("nrow", "ncol", "n_common_cols", "type_match_pct",
                           "missing_orig_pct", "missing_syn_pct"),
    original           = c(nrow(orig), ncol(orig), length(common_cols),
                           NA_real_, miss_orig, NA_real_),
    synthetic          = c(nrow(syn),  ncol(syn),  NA_integer_,
                           NA_real_, NA_real_, miss_syn),
    value              = c(NA_real_, NA_real_, NA_real_,
                            if (length(type_match) == 0) NA_real_ else sum(type_match) / length(type_match) * 100,
                           NA_real_, NA_real_)
  )
}

# ===========================================================================
# Numeric comparison
# ===========================================================================

#' Safe two-sample test p-value.
#'
#' Returns `NA_real_` instead of erroring on degenerate input.
#' @keywords internal
#' @noRd
safe_test_p <- function(expr) {
  tryCatch(suppressWarnings(expr$p.value), error = function(e) NA_real_)
}

compare_numeric <- function(orig, syn) {
  num_cols <- names(orig)[vapply(orig, function(x) {
    is.numeric(x) && !haven::is.labelled(x)
  }, logical(1))]
  num_cols <- intersect(num_cols, names(syn))
  num_cols <- num_cols[vapply(num_cols, function(nm) is.numeric(syn[[nm]]), logical(1))]

  if (length(num_cols) == 0) {
    return(tibble::tibble(
      variable = character(0), mean_orig = double(0), mean_syn = double(0),
      sd_orig = double(0), sd_syn = double(0),
      median_orig = double(0), median_syn = double(0),
      iqr_orig = double(0), iqr_syn = double(0),
      missing_orig_pct = double(0), missing_syn_pct = double(0),
      std_diff = double(0), sd_ratio = double(0),
      median_std_diff = double(0),
      mean_p = double(0), sd_p = double(0), median_p = double(0)
    ))
  }

  out <- lapply(num_cols, function(nm) {
    x <- orig[[nm]]
    y <- syn[[nm]]

    x_obs <- x[!is.na(x)]
    y_obs <- y[!is.na(y)]

    if (length(x_obs) == 0) {
      return(tibble::tibble(
        variable = nm, mean_orig = NA_real_, mean_syn = mean(y_obs),
        sd_orig = NA_real_, sd_syn = stats::sd(y_obs),
        median_orig = NA_real_, median_syn = stats::median(y_obs),
        iqr_orig = NA_real_, iqr_syn = stats::IQR(y_obs),
        missing_orig_pct = 100, missing_syn_pct = sum(is.na(y)) / length(y) * 100,
        std_diff = NA_real_, sd_ratio = NA_real_,
        median_std_diff = NA_real_,
        mean_p = NA_real_, sd_p = NA_real_, median_p = NA_real_
      ))
    }

    mean_o <- mean(x_obs)
    sd_o   <- stats::sd(x_obs)
    mean_s <- if (length(y_obs) > 0) mean(y_obs) else NA_real_
    sd_s   <- if (length(y_obs) > 0) stats::sd(y_obs) else NA_real_

    std_diff <- if (sd_o > 0 && length(y_obs) > 0) {
      (mean_s - mean_o) / sd_o
    } else {
      NA_real_
    }

    iqr_o <- stats::IQR(x_obs)
    median_std_diff <- if (iqr_o > 0 && length(y_obs) > 0) {
      (stats::median(y_obs) - stats::median(x_obs)) / iqr_o
    } else {
      NA_real_
    }

    tibble::tibble(
      variable       = nm,
      mean_orig      = mean_o,
      mean_syn       = mean_s,
      sd_orig        = sd_o,
      sd_syn         = sd_s,
      median_orig    = stats::median(x_obs),
      median_syn     = if (length(y_obs) > 0) stats::median(y_obs) else NA_real_,
      iqr_orig       = stats::IQR(x_obs),
      iqr_syn        = if (length(y_obs) > 0) stats::IQR(y_obs) else NA_real_,
      missing_orig_pct = sum(is.na(x)) / length(x) * 100,
      missing_syn_pct  = sum(is.na(y)) / length(y) * 100,
      std_diff       = std_diff,
      sd_ratio       = if (!is.na(sd_o) && sd_o > 0 && length(y_obs) > 0) sd_s / sd_o else NA_real_,
      median_std_diff = median_std_diff,
      mean_p         = if (length(y_obs) > 1 && length(x_obs) > 1) safe_test_p(stats::t.test(x_obs, y_obs)) else NA_real_,
      sd_p           = if (length(y_obs) > 1 && length(x_obs) > 1) safe_test_p(stats::var.test(x_obs, y_obs)) else NA_real_,
      median_p       = if (length(y_obs) > 1 && length(x_obs) > 1) safe_test_p(stats::wilcox.test(x_obs, y_obs)) else NA_real_
    )
  })

  dplyr::bind_rows(out)
}

# ===========================================================================
# Categorical comparison
# ===========================================================================

compare_categorical <- function(orig, syn) {
  cat_types <- c("character", "factor", "logical")
  cat_cols <- names(orig)[vapply(orig, function(x) {
    any(cat_types %in% class(x)) || is.character(x) || is.factor(x) || is.logical(x) || haven::is.labelled(x)
  }, logical(1))]
  cat_cols <- intersect(cat_cols, names(syn))

  if (length(cat_cols) == 0) {
    return(tibble::tibble(
      variable = character(0), n_levels_orig = integer(0),
      n_levels_syn = integer(0), top_5_orig = character(0),
      top_5_syn = character(0), missing_orig_pct = double(0),
      missing_syn_pct = double(0), tvd = double(0)
    ))
  }

  out <- lapply(cat_cols, function(nm) {
    x <- as.character(orig[[nm]])
    y <- as.character(syn[[nm]])

    x_obs <- x[!is.na(x)]
    y_obs <- y[!is.na(y)]

    tx <- sort(table(x_obs), decreasing = TRUE)
    ty <- sort(table(y_obs), decreasing = TRUE)

    top5_orig <- paste(utils::head(names(tx), 5), collapse = "; ")
    top5_syn  <- paste(utils::head(names(ty), 5), collapse = "; ")

    # total variation distance
    all_levels <- union(names(tx), names(ty))
    px <- stats::setNames(rep(0, length(all_levels)), all_levels)
    py <- stats::setNames(rep(0, length(all_levels)), all_levels)
    if (length(x_obs) > 0) px[names(tx)] <- as.numeric(tx) / length(x_obs)
    if (length(y_obs) > 0) py[names(ty)] <- as.numeric(ty) / length(y_obs)
    tvd <- 0.5 * sum(abs(px - py))

    tibble::tibble(
      variable        = nm,
      n_levels_orig   = length(tx),
      n_levels_syn    = length(ty),
      top_5_orig      = top5_orig,
      top_5_syn       = top5_syn,
      missing_orig_pct = sum(is.na(x)) / length(x) * 100,
      missing_syn_pct  = sum(is.na(y)) / length(y) * 100,
      tvd             = tvd
    )
  })

  dplyr::bind_rows(out)
}

# ===========================================================================
# Relationship comparison (Pearson correlations)
# ===========================================================================

compare_relationship <- function(orig, syn) {
  num_cols <- names(orig)[vapply(orig, function(x) {
    is.numeric(x) && !haven::is.labelled(x)
  }, logical(1))]
  num_cols <- intersect(num_cols, names(syn))
  num_cols <- num_cols[vapply(num_cols, function(nm) {
    if (!is.numeric(syn[[nm]])) {
      return(FALSE)
    }
    vo <- stats::var(orig[[nm]], na.rm = TRUE)
    vs <- stats::var(syn[[nm]], na.rm = TRUE)
    isTRUE(vo > 0) && isTRUE(vs > 0)
  }, logical(1))]

  if (length(num_cols) < 2) {
    cli::cli_inform(c(
      "i" = "Not enough numeric columns ({length(num_cols)}) for correlation comparison.",
      " " = "Need at least 2 numeric columns with non-zero variance."
    ))
    return(tibble::tibble(
      var1 = character(0), var2 = character(0),
      cor_orig = double(0), cor_syn = double(0), cor_diff = double(0)
    ))
  }

  orig_num <- orig[, num_cols, drop = FALSE]
  syn_num  <- syn[, num_cols, drop = FALSE]

  cor_orig <- stats::cor(orig_num, use = "pairwise.complete.obs")
  cor_syn  <- stats::cor(syn_num,  use = "pairwise.complete.obs")
  cor_diff <- cor_syn - cor_orig

  # Convert to long form
  rows <- list()
  for (i in seq_len(nrow(cor_diff))) {
    for (j in seq_len(ncol(cor_diff))) {
      if (i < j) {
        rows[[length(rows) + 1]] <- tibble::tibble(
          var1     = num_cols[i],
          var2     = num_cols[j],
          cor_orig = cor_orig[i, j],
          cor_syn  = cor_syn[i, j],
          cor_diff = cor_diff[i, j]
        )
      }
    }
  }

  if (length(rows) == 0) {
    return(tibble::tibble(
      var1 = character(0), var2 = character(0),
      cor_orig = double(0), cor_syn = double(0), cor_diff = double(0)
    ))
  }

  dplyr::bind_rows(rows)
}

# ===========================================================================
# Print method
# ===========================================================================

#' @export
print.dataganger_comparison <- function(x, ...) {
  cli::cli_h1("DataGangeR Comparison")

  # Dataset-level
  cli::cli_h2("Dataset")
  ds <- x$dataset
  nrow_orig <- ds$original[ds$metric == "nrow"]
  nrow_syn  <- ds$synthetic[ds$metric == "nrow"]
  ncol_orig <- ds$original[ds$metric == "ncol"]
  ncol_syn  <- ds$synthetic[ds$metric == "ncol"]
  type_match <- ds$value[ds$metric == "type_match_pct"]

  cli::cli_li("Rows: {nrow_orig} (original) -> {nrow_syn} (synthetic)")
  cli::cli_li("Columns: {ncol_orig} (original) -> {ncol_syn} (synthetic)")
  if (!is.na(type_match)) {
    cli::cli_li("Type match: {round(type_match, 1)}%")
  }
  miss_orig <- ds$original[ds$metric == "missing_orig_pct"]
  miss_syn  <- ds$synthetic[ds$metric == "missing_syn_pct"]
  cli::cli_li("Missing: {round(miss_orig, 1)}% (original) -> {round(miss_syn, 1)}% (synthetic)")

  # Numeric -- top 3 by |std_diff|
  if (nrow(x$numeric) > 0) {
    cli::cli_h2("Numeric -- top 3 by |standardized difference|")
    num <- x$numeric
    num <- num[order(abs(num$std_diff), decreasing = TRUE), ]
    n_show <- min(3, nrow(num))
    for (i in seq_len(n_show)) {
      r <- num[i, ]
      cli::cli_li("{.field {r$variable}}: std diff = {round(r$std_diff, 3)}")
      cli::cli_text("  Orig mean (SD): {round(r$mean_orig, 2)} ({round(r$sd_orig, 2)})")
    }
  }

  # Categorical -- top 3 by TVD
  if (nrow(x$categorical) > 0) {
    cli::cli_h2("Categorical -- top 3 by total variation distance")
    cat <- x$categorical
    cat <- cat[order(cat$tvd, decreasing = TRUE), ]
    n_show <- min(3, nrow(cat))
    for (i in seq_len(n_show)) {
      r <- cat[i, ]
      cli::cli_li("{.field {r$variable}}: TVD = {round(r$tvd, 3)}")
      cli::cli_text("  Levels: {r$n_levels_orig} (orig) -> {r$n_levels_syn} (syn)")
    }
  }

  # Relationship
  if (nrow(x$relationship) > 0) {
    cli::cli_h2("Relationship -- top 3 correlation diffs")
    rel <- x$relationship
    rel <- rel[order(abs(rel$cor_diff), decreasing = TRUE), ]
    n_show <- min(3, nrow(rel))
    for (i in seq_len(n_show)) {
      r <- rel[i, ]
      cli::cli_li("{.field {r$var1}} x {.field {r$var2}}: diff = {round(r$cor_diff, 3)}")
    }
  }

  # Privacy flags
  if (!is.null(x$privacy_flags) && nrow(x$privacy_flags) > 0) {
    cli::cli_h2("Privacy flags")
    pf <- x$privacy_flags
    high_n <- sum(pf$severity == "HIGH")
    med_n  <- sum(pf$severity == "MEDIUM")
    low_n  <- sum(pf$severity == "LOW")
    cli::cli_li("HIGH: {high_n}  MEDIUM: {med_n}  LOW: {low_n}")
  }

  invisible(x)
}

# ===========================================================================
# plot_comparison() helper [3.9]
# ===========================================================================

#' Plot comparison summaries
#'
#' Produces two bar charts comparing original and synthetic data:
#' standardized differences for numeric columns and total variation
#' distance for categorical columns. Requires `ggplot2` (Suggests).
#'
#' @param comparison A `dataganger_comparison` object from
#'   [compare_synthetic()].
#'
#' @return Invisibly, a list with two `ggplot` objects: `numeric` and
#'   `categorical`. Each is `NULL` if no columns of that type exist.
#' @export
#'
#' @examples
#' dat <- data.frame(x = 1:10, y = letters[1:10])
#' spec <- synth_spec(purpose = "demo")
#' syn <- synthesize_data(dat, spec)
#' cmp <- compare_synthetic(dat, syn)
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   plot_comparison(cmp)
#' }
plot_comparison <- function(comparison) {
  rlang::check_installed("ggplot2", reason = "to use `plot_comparison()`")

  plots <- list(numeric = NULL, categorical = NULL)

  # Numeric plot
  if (nrow(comparison$numeric) > 0) {
    num <- comparison$numeric
    num$abs_diff <- abs(num$std_diff)
    num$color <- cut(num$abs_diff,
      breaks = c(-Inf, 0.1, 0.2, Inf),
      labels = c("green", "yellow", "red")
    )
    num <- num[order(num$abs_diff), ]
    num$variable <- factor(num$variable, levels = num$variable)

    color_map <- c(green = "#4CAF50", yellow = "#FFC107", red = "#F44336")

    plots$numeric <- ggplot2::ggplot(
      num, ggplot2::aes(x = variable, y = std_diff, fill = color)
    ) +
      ggplot2::geom_col() +
      ggplot2::scale_fill_manual(values = color_map, guide = "none") +
      ggplot2::labs(
        title = "Standardized difference (numeric columns)",
        x = "", y = "Standardized difference"
      ) +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  }

  # Categorical plot
  if (nrow(comparison$categorical) > 0) {
    cat <- comparison$categorical
    cat$color <- cut(cat$tvd,
      breaks = c(-Inf, 0.1, 0.2, Inf),
      labels = c("green", "yellow", "red")
    )
    cat <- cat[order(cat$tvd), ]
    cat$variable <- factor(cat$variable, levels = cat$variable)

    color_map <- c(green = "#4CAF50", yellow = "#FFC107", red = "#F44336")

    plots$categorical <- ggplot2::ggplot(
      cat, ggplot2::aes(x = variable, y = tvd, fill = color)
    ) +
      ggplot2::geom_col() +
      ggplot2::scale_fill_manual(values = color_map, guide = "none") +
      ggplot2::labs(
        title = "Total variation distance (categorical columns)",
        x = "", y = "Total variation distance"
      ) +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  }

  invisible(plots)
}
