# Marginal synthesis (Level 2)
#
# Internal function. Synthesizes each column independently using
# the helpers from synth-helpers.R. Honors spec parameters for
# missingness, rare-level merging, date coarsening, and free text.

synthesize_marginal <- function(data, spec, roles = NULL) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame")
  }

  n <- spec$n %||% nrow(data)

  if (n == 0) {
    # 0-row request: return schema
    return(synthesize_schema(data, spec, roles))
  }

  rare_min_n <- spec$rare_level_min_n %||% 5
  merge_rare  <- spec$merge_rare %||% TRUE
  coarsen     <- spec$coarsen_dates %||% TRUE
  missingness <- spec$preserve_missingness %||% "approx"
  free_text_s <- spec$free_text_strategy %||% "drop"

  # Build role lookup if available
  role_lookup <- NULL
  if (!is.null(roles) && "variable" %in% names(roles) &&
      "recommended_role" %in% names(roles)) {
    role_lookup <- stats::setNames(roles$recommended_role, roles$variable)
  }

  cols <- vector("list", ncol(data))
  names(cols) <- names(data)

  # --- remove_ids guard (C11 privacy hardening) ---
  if (isTRUE(spec$remove_ids) && !is.null(role_lookup)) {
    id_cols <- names(role_lookup)[role_lookup == "ID candidate"]
    if (length(id_cols) > 0) {
      cli::cli_inform(c(
        "i" = "{.arg remove_ids} is TRUE: masking {length(id_cols)} ID column{?s}",
        " " = "{.val {id_cols}}"
      ))
    }
  }

  for (i in seq_len(ncol(data))) {
    col_name <- names(data)[i]
    x <- data[[i]]

    # Determine role for this column
    role <- role_lookup[[col_name]] %||% "unknown"

    # remove_ids: mask ID columns with NA
    if (isTRUE(spec$remove_ids) && !is.null(role_lookup) &&
        role == "ID candidate") {
      cols[[i]] <- typed_missing_vector(x, n)
      next
    }

    # Free text handling
    if (role == "free text" || is_free_text_candidate(x)) {
      cols[[i]] <- synth_free_text(x, n, strategy = free_text_s)
      next
    }

    # Dispatch by type
    if (all(is.na(x))) {
      cols[[i]] <- typed_missing_vector(x, n)
      next
    }

    if (haven::is.labelled(x)) {
      cols[[i]] <- synth_labelled(x, n,
        rare_level_min_n = rare_min_n,
        merge_rare = merge_rare,
        missing_strategy = missingness
      )
    } else if (is.numeric(x)) {
      cols[[i]] <- synth_numeric(x, n, missing_strategy = missingness)
    } else if (is.character(x)) {
      cols[[i]] <- synth_character(x, n,
        rare_level_min_n = rare_min_n,
        merge_rare = merge_rare,
        missing_strategy = missingness
      )
    } else if (is.factor(x)) {
      cols[[i]] <- synth_categorical(x, n,
        rare_level_min_n = rare_min_n,
        merge_rare = merge_rare,
        missing_strategy = missingness
      )
    } else if (inherits(x, "Date")) {
      cols[[i]] <- synth_date(x, n,
        coarsen_dates = coarsen,
        missing_strategy = missingness
      )
    } else if (inherits(x, "POSIXct")) {
      # POSIXct: sample uniformly within observed range
      cols[[i]] <- synth_posixct(x, n,
        coarsen_dates = coarsen,
        missing_strategy = missingness
      )
    } else if (is.logical(x)) {
      cols[[i]] <- synth_logical(x, n, missing_strategy = missingness)
    } else {
      # Fallback: treat as character
      cli::cli_warn(c(
        "Column {.val {col_name}} has unrecognised type; treating as character"
      ))
      cols[[i]] <- synth_character(as.character(x), n,
        rare_level_min_n = rare_min_n,
        merge_rare = merge_rare,
        missing_strategy = missingness
      )
    }
  }

  out <- tibble::as_tibble(cols)
  if (missingness == "exact") {
    mask <- build_na_mask(data, n)
    out  <- apply_joint_mask(out, mask)
  }
  out
}

# POSIXct synthesis helper
synth_posixct <- function(x, n, coarsen_dates = TRUE, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(as.POSIXct(NA), n))
  }

  x_obs <- x[!is.na(x)]
  min_ts <- min(x_obs)
  max_ts <- max(x_obs)

  range_secs <- as.numeric(difftime(max_ts, min_ts, units = "secs"))
  if (range_secs <= 0) {
    synth <- rep(min_ts, n)
  } else {
    synth <- min_ts + stats::runif(n, min = 0, max = range_secs)
  }

  if (isTRUE(coarsen_dates)) {
    synth <- coarsen_posixct_to_day(synth)
  }

  synth <- apply_missingness(synth, x, n, missing_strategy)
  synth
}

coarsen_posixct_to_day <- function(ts) {
  tz <- attr(ts, "tzone") %||% ""
  as.POSIXct(format(ts, "%Y-%m-%d", tz = tz), tz = tz)
}

typed_missing_vector <- function(x, n) {
  if (haven::is.labelled(x)) {
    return(rep(NA_character_, n))
  }
  if (inherits(x, "Date")) {
    return(rep(as.Date(NA), n))
  }
  if (inherits(x, "POSIXct")) {
    return(rep(as.POSIXct(NA, tz = attr(x, "tzone") %||% "UTC"), n))
  }
  if (is.factor(x)) {
    return(factor(rep(NA_character_, n), levels = levels(x)))
  }
  if (is.numeric(x)) {
    return(rep(NA_real_, n))
  }
  if (is.logical(x)) {
    return(rep(NA, n))
  }
  rep(NA_character_, n)
}
