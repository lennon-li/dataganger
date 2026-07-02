# Internal synthesis helpers for dataganger
#
# Each helper synthesises a single column independently.
# All return vectors of length n.
#
# Constraints:
# - Never use set.seed() -- the caller wraps with withr::with_seed()
# - Never pass raw haven_labelled into base R distribution functions
# - All-NA inputs -> all-NA output of same type

# ===========================================================================
# Numeric synthesis [2.5]
# ===========================================================================

synth_numeric <- function(x, n, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(NA_real_, n))
  }

  x_obs <- x[!is.na(x)]
  n_obs <- length(x_obs)

  # Sample from empirical CDF with jitter
  synth <- sample(x_obs, size = n, replace = TRUE)

  # Add small Gaussian jitter scaled to IQR/10
  iqr_val <- stats::IQR(x_obs, na.rm = TRUE)
  if (iqr_val > 0) {
    jitter_sd <- iqr_val / 10
    synth <- synth + stats::rnorm(n, mean = 0, sd = jitter_sd)
  }

  # Truncate to observed range
  obs_min <- min(x_obs)
  obs_max <- max(x_obs)
  synth <- pmax(synth, obs_min)
  synth <- pmin(synth, obs_max)

  # Apply missingness
  synth <- apply_missingness(synth, x, n, missing_strategy)

  synth
}

# ===========================================================================
# Categorical synthesis [2.6]
# ===========================================================================

synth_categorical <- function(x, n, rare_level_min_n = 5,
                              merge_rare = TRUE, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(NA_character_, n))
  }

  x_obs <- x[!is.na(x)]

  # Handle factor levels
  if (is.factor(x_obs)) {
    levs <- levels(x_obs)
    x_obs <- as.character(x_obs)
  } else {
    levs <- unique(x_obs)
  }

  # Count occurrences
  tbl <- table(x_obs)
  tbl_nms <- names(tbl)
  tbl_counts <- as.integer(tbl)

  # Rare-level merge
  if (isTRUE(merge_rare)) {
    rare_mask <- tbl_counts < rare_level_min_n
    if (any(rare_mask)) {
      # Replace rare in observed data
      rare_vals <- tbl_nms[rare_mask]
      x_obs[x_obs %in% rare_vals] <- ".other"
      # Recompute table
      tbl <- table(x_obs)
      tbl_nms <- names(tbl)
      tbl_counts <- as.integer(tbl)
      # Track whether ".other" exists in levels
      levs <- c(levs[!levs %in% rare_vals], ".other")
    }
  }

  # Proportion sampling
  probs <- tbl_counts / sum(tbl_counts)
  synth <- sample(tbl_nms, size = n, replace = TRUE, prob = probs)

  # Convert back to factor if input was factor
  if (is.factor(x)) {
    if (".other" %in% synth && !".other" %in% levels(x)) {
      all_levs <- c(levels(x), ".other")
    } else {
      all_levs <- levels(x)
    }
    synth <- factor(synth, levels = all_levs)
  }

  # Apply missingness
  synth <- apply_missingness(synth, x, n, missing_strategy)

  synth
}

# ===========================================================================
# Date synthesis [2.7]
# ===========================================================================

synth_date <- function(x, n, coarsen_dates = TRUE, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(as.Date(NA), n))
  }

  x_obs <- x[!is.na(x)]
  min_date <- min(x_obs)
  max_date <- max(x_obs)

  # Random uniform dates within observed range
  range_days <- as.integer(max_date - min_date)
  if (range_days <= 0) {
    synth <- rep(min_date, n)
  } else {
    synth <- min_date + sample(0:range_days, size = n, replace = TRUE)
  }

  # Coarsen to month if requested
  if (isTRUE(coarsen_dates)) {
    synth <- coarsen_to_month(synth)
  }

  # Apply missingness
  synth <- apply_missingness(synth, x, n, missing_strategy)

  synth
}

coarsen_to_month <- function(dates) {
  as.Date(format(dates, "%Y-%m-01"))
}

coarsen_to_quarter <- function(dates) {
  qtr <- quarters(dates)
  yr <- format(dates, "%Y")
  qtr_month <- c(Q1 = "01", Q2 = "04", Q3 = "07", Q4 = "10")
  as.Date(paste0(yr, "-", qtr_month[qtr], "-01"))
}

coarsen_to_year <- function(dates) {
  as.Date(paste0(format(dates, "%Y"), "-01-01"))
}

# ===========================================================================
# Logical synthesis [2.8]
# ===========================================================================

synth_logical <- function(x, n, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(NA, n))
  }

  x_obs <- x[!is.na(x)]
  p_true <- sum(x_obs) / length(x_obs)

  synth <- stats::runif(n) < p_true

  synth <- apply_missingness(synth, x, n, missing_strategy)
  synth
}

# ===========================================================================
# Character (non-free-text) synthesis [2.8]
# ===========================================================================

synth_character <- function(x, n, rare_level_min_n = 5,
                            merge_rare = TRUE, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(NA_character_, n))
  }

  # Treat as categorical
  x_obs <- x[!is.na(x)]
  tbl <- table(x_obs)
  tbl_nms <- names(tbl)
  tbl_counts <- as.integer(tbl)

  # Rare-level merge
  if (isTRUE(merge_rare)) {
    rare_mask <- tbl_counts < rare_level_min_n
    if (any(rare_mask)) {
      rare_vals <- tbl_nms[rare_mask]
      x_obs[x_obs %in% rare_vals] <- ".other"
      tbl <- table(x_obs)
      tbl_nms <- names(tbl)
      tbl_counts <- as.integer(tbl)
    }
  }

  probs <- tbl_counts / sum(tbl_counts)
  synth <- sample(tbl_nms, size = n, replace = TRUE, prob = probs)

  synth <- apply_missingness(synth, x, n, missing_strategy)
  synth
}

# ===========================================================================
# haven_labelled synthesis [2.8]
# ===========================================================================

synth_labelled <- function(x, n, rare_level_min_n = 5,
                           merge_rare = TRUE, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(NA_character_, n))
  }

  # Convert to factor for synthesis
  x_factor <- haven::as_factor(x)
  synth_factor <- synth_categorical(
    x_factor, n,
    rare_level_min_n = rare_level_min_n,
    merge_rare = merge_rare,
    missing_strategy = missing_strategy
  )

  as.character(synth_factor)
}

# ===========================================================================
# Free text handling [2.8]
# ===========================================================================

synth_free_text <- function(x, n, strategy = "drop") {
  if (strategy == "drop") {
    return(rep(NA_character_, n))
  }
  if (strategy == "redact") {
    return(rep("[REDACTED]", n))
  }
  cli::cli_abort("Unknown free_text_strategy: {.val {strategy}}")
}


# ===========================================================================
# Missingness application (R5: independent per-column Bernoulli)
# ===========================================================================

apply_missingness <- function(synth, original, n, strategy) {
  if (strategy == "none") {
    return(synth)
  }

  if (strategy == "approx") {
    obs_na_rate <- sum(is.na(original)) / length(original)
    if (obs_na_rate > 0) {
      na_mask <- stats::runif(n) < obs_na_rate
      synth[na_mask] <- NA
    }
    return(synth)
  }

  if (strategy == "exact") {
    return(synth)
  }

  synth
}

# ===========================================================================
# Joint missingness mask helpers for preserve_missingness = "exact"
# ===========================================================================

build_na_mask <- function(data, n) {
  M <- is.na(data)
  if (n == nrow(data)) return(M)
  row_idx <- sample(nrow(data), size = n, replace = TRUE)
  M[row_idx, , drop = FALSE]
}

apply_joint_mask <- function(out, mask) {
  for (col in intersect(colnames(mask), names(out))) {
    out[[col]][mask[, col]] <- NA
  }
  out
}
