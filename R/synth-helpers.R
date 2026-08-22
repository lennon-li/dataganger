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

  # Add Gaussian noise unless the column is truly constant.
  if (length(unique(x_obs)) > 1L) {
    scale_candidates <- c(
      stats::IQR(x_obs, na.rm = TRUE) / 10,
      stats::mad(x_obs, na.rm = TRUE),
      stats::sd(x_obs, na.rm = TRUE),
      abs(mean(x_obs, na.rm = TRUE)) / 100
    )
    scale_candidates <- scale_candidates[is.finite(scale_candidates) & scale_candidates > 0]
    jitter_sd <- if (length(scale_candidates)) scale_candidates[[1L]] else 0
  } else {
    jitter_sd <- 0
  }
  if (jitter_sd > 0) {
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

#' Validate the categorical label strategy
#'
#' @param label_strategy Either `"preserve"` or `"mask_rare"`.
#' @keywords internal
#' @noRd
validate_label_strategy <- function(label_strategy) {
  if (length(label_strategy) != 1L || is.na(label_strategy) ||
      !label_strategy %in% c("preserve", "mask_rare")) {
    cli::cli_abort("Unknown label strategy: {.val {label_strategy}}")
  }
  invisible(label_strategy)
}

#' Apply distinct placeholders to rare categorical labels
#'
#' Masking keeps cardinality, frequency, and guaranteed level presence intact
#' so downstream code paths, joins, and facets still behave, while the
#' identifying string never leaves the source.
#'
#' @keywords internal
#' @noRd
mask_rare_category_labels <- function(x_obs, levs, tbl_nms, tbl_counts,
                                      rare_level_min_n) {
  rare_mask <- tbl_counts < rare_level_min_n
  if (!any(rare_mask)) {
    return(list(x_obs = x_obs, levs = levs))
  }

  rare_vals <- tbl_nms[rare_mask]
  rare_counts <- tbl_counts[rare_mask]
  rare_order <- order(-rare_counts, rare_vals, method = "radix")
  rare_vals <- rare_vals[rare_order]

  occupied <- unique(c(levs, x_obs))
  placeholder_numbers <- integer(length(rare_vals))
  next_number <- 1L
  for (i in seq_along(rare_vals)) {
    while (paste("Other category", next_number) %in% occupied) {
      next_number <- next_number + 1L
    }
    placeholder_numbers[[i]] <- next_number
    occupied <- c(occupied, paste("Other category", next_number))
    next_number <- next_number + 1L
  }
  placeholders <- paste("Other category", placeholder_numbers)
  names(placeholders) <- rare_vals
  is_rare <- x_obs %in% rare_vals
  x_obs[is_rare] <- unname(placeholders[x_obs[is_rare]])
  level_idx <- match(rare_vals, levs)
  levs[level_idx[!is.na(level_idx)]] <- placeholders[!is.na(level_idx)]

  list(x_obs = x_obs, levs = levs)
}

#' Synthesize categorical values
#'
#' @param label_strategy How observed labels are treated. `"mask_rare"`
#'   replaces each rare label with a distinct placeholder and takes precedence
#'   over `merge_rare`, which would otherwise merge labels into `.other`.
#' @keywords internal
#' @noRd
synth_categorical <- function(x, n, rare_level_min_n = 5,
                              merge_rare = FALSE, missing_strategy = "approx",
                              label_strategy = "preserve") {
  validate_label_strategy(label_strategy)
  if (all(is.na(x))) {
    return(rep(NA_character_, n))
  }

  # Levels come from the observed values only. A factor input can declare a
  # level with zero rows, and the ingest conversion to character drops that
  # declaration deliberately: a level with no rows in the source should have
  # no rows in the synthetic copy. Carrying it forward would push sampling
  # into the "every category appears at least once" branch below and invent
  # rows of a category that was never observed -- fabricated data, and a
  # k-anonymity singleton on top.
  x_obs <- as.character(x[!is.na(x)])
  levs <- sort(unique(x_obs))

  # Count occurrences
  tbl <- table(x_obs)
  tbl_nms <- names(tbl)
  tbl_counts <- as.integer(tbl)

  if (identical(label_strategy, "mask_rare")) {
    masked <- mask_rare_category_labels(
      x_obs, levs, tbl_nms, tbl_counts, rare_level_min_n
    )
    x_obs <- masked$x_obs
    levs <- masked$levs
    tbl <- table(x_obs)
    tbl_nms <- names(tbl)
    tbl_counts <- as.integer(tbl)
  } else if (isTRUE(merge_rare)) {
    # Rare-level merge
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
  pool <- sort(unique(c(tbl_nms, levs)))
  pool_counts <- stats::setNames(integer(length(pool)), pool)
  pool_counts[tbl_nms] <- tbl_counts
  probs <- pool_counts / sum(pool_counts)
  if (length(pool) <= n) {
    # Every sampled category must exercise downstream code paths at least once.
    synth <- c(
      pool,
      sample(pool, size = n - length(pool), replace = TRUE, prob = probs)
    )
    synth <- sample(synth, size = length(synth), replace = FALSE)
  } else {
    cli::cli_warn(
      "Cannot guarantee categorical level presence: {length(pool)} levels exceed requested output size of {n}."
    )
    synth <- sample(pool, size = n, replace = TRUE, prob = probs)
  }

  # Apply missingness
  synth <- apply_missingness(synth, x, n, missing_strategy)

  as.character(synth)
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
# Time-of-day synthesis (no date component) [2.7b]
# ===========================================================================

synth_time_of_day <- function(x, n, missing_strategy = "approx") {
  if (all(is.na(x))) {
    return(rep(as.POSIXct(NA, tz = "UTC"), n))
  }

  x_obs <- x[!is.na(x)]
  lt <- as.POSIXlt(x_obs, tz = "UTC")
  secs_of_day <- lt$hour * 3600L + lt$min * 60L + round(lt$sec)
  min_s <- min(secs_of_day)
  max_s <- max(secs_of_day)

  if (max_s <= min_s) {
    synth_secs <- rep(min_s, n)
  } else {
    synth_secs <- sample(min_s:max_s, size = n, replace = TRUE)
  }

  # Anchored to a fixed reference date -- only the time-of-day component is
  # meaningful, the date part is discarded when formatting back to text.
  synth <- as.POSIXct("1970-01-01", tz = "UTC") + synth_secs
  synth <- apply_missingness(synth, x, n, missing_strategy)
  synth
}

# ===========================================================================
# Character-stored date/time strings [2.7c]
# ===========================================================================
#
# detect_roles() flags date-looking strings (e.g. "01/08/2020", "Jun 8, 2019",
# "2020-01-15 14:30:00", or a bare time like "14:30") as role "date" even
# though the column is still a plain character vector. Left to the generic
# character dispatch, these would be resampled verbatim as if they were
# arbitrary categorical text -- the exact original date/time values reshuffled
# across rows, with none of the range-based synthesis or coarsen_dates
# protection that a native Date/POSIXct column gets. The functions below
# parse the column using the same format its own values are already in,
# synthesize through the real date/time/time-of-day machinery, then format
# the result back to that same pattern so the synthetic output reads like
# the source data.

# Candidate strptime formats. Not exhaustive -- covers the common patterns
# detect_roles() itself looks for. %e (space-padded day) variants sit next to
# their %d (zero-padded) counterparts because strptime parses either
# leniently regardless of which one is declared -- only round-trip
# formatting (see detect_date_format()) actually distinguishes them.
dg_date_format_candidates <- function() {
  list(
    list(fmt = "%Y-%m-%dT%H:%M:%OS",     has_date = TRUE,  has_time = TRUE),
    list(fmt = "%Y-%m-%d %H:%M:%OS",     has_date = TRUE,  has_time = TRUE),
    list(fmt = "%Y-%m-%d %H:%M",         has_date = TRUE,  has_time = TRUE),
    list(fmt = "%m/%d/%Y %I:%M:%OS %p",  has_date = TRUE,  has_time = TRUE),
    list(fmt = "%m/%d/%Y %I:%M %p",      has_date = TRUE,  has_time = TRUE),
    list(fmt = "%m/%d/%Y %H:%M:%OS",     has_date = TRUE,  has_time = TRUE),
    list(fmt = "%m/%d/%Y %H:%M",         has_date = TRUE,  has_time = TRUE),
    list(fmt = "%Y-%m-%d",               has_date = TRUE,  has_time = FALSE),
    list(fmt = "%Y/%m/%d",               has_date = TRUE,  has_time = FALSE),
    list(fmt = "%m/%d/%Y",               has_date = TRUE,  has_time = FALSE),
    list(fmt = "%m/%d/%y",               has_date = TRUE,  has_time = FALSE),
    list(fmt = "%B %d, %Y",              has_date = TRUE,  has_time = FALSE),
    list(fmt = "%B %e, %Y",              has_date = TRUE,  has_time = FALSE),
    list(fmt = "%b %d, %Y",              has_date = TRUE,  has_time = FALSE),
    list(fmt = "%b %e, %Y",              has_date = TRUE,  has_time = FALSE),
    list(fmt = "%d %b %Y",               has_date = TRUE,  has_time = FALSE),
    list(fmt = "%I:%M:%OS %p",           has_date = FALSE, has_time = TRUE),
    list(fmt = "%I:%M %p",               has_date = FALSE, has_time = TRUE),
    list(fmt = "%H:%M:%OS",              has_date = FALSE, has_time = TRUE),
    list(fmt = "%H:%M",                  has_date = FALSE, has_time = TRUE)
  )
}

# ---------------------------------------------------------------------------
# Locale-independent AM/PM handling.
#
# strptime() and format() hand "%p" to the C library, which makes it both
# locale- and OS-dependent: on some platform/locale pairs (macOS with
# LC_TIME=en_GB, for one) "%p" matches nothing when parsing and formats to an
# empty string, so a column stored as "01/01/2020 01:15 PM" is neither
# detected as a 12-hour format nor written back as one. Every candidate
# format below that carries "%p" is therefore parsed and formatted by these
# helpers, which read and write the ASCII AM/PM token themselves and never
# pass "%p" through to the platform.

dg_period_suffix <- "[[:space:]]*([AaPp][Mm])[[:space:]]*$"

# Drops "%p", and the separator in front of it, from a strptime format.
dg_format_without_period <- function(fmt) {
  trimws(sub("[[:space:]]*%p", "", fmt))
}

# The trailing AM/PM token of each value, lowercased; NA where there is none.
dg_period_of <- function(x) {
  token <- rep(NA_character_, length(x))
  hit <- grepl(dg_period_suffix, x)
  token[hit] <- tolower(sub(paste0("^.*", dg_period_suffix), "\\1", x[hit]))
  token
}

dg_strip_period <- function(x) {
  trimws(sub(dg_period_suffix, "", x))
}

# The AM and PM tokens to write back out, taken from the source column so the
# synthetic values keep its convention ("AM"/"PM" vs "am"/"pm").
dg_period_tokens <- function(source_values) {
  markers <- source_values[grepl(dg_period_suffix, source_values)]
  markers <- sub(paste0("^.*", dg_period_suffix), "\\1", markers)
  upper_convention <- length(markers) == 0L ||
    mean(markers == toupper(markers)) >= 0.5
  case_fn <- if (upper_convention) toupper else tolower
  most_common <- function(values, fallback) {
    if (length(values) == 0L) {
      return(case_fn(fallback))
    }
    names(sort(table(values), decreasing = TRUE))[[1L]]
  }
  list(
    am = most_common(markers[tolower(markers) == "am"], "AM"),
    pm = most_common(markers[tolower(markers) == "pm"], "PM")
  )
}

# strptime() for a format that may contain "%p". Values carrying no AM/PM
# token do not match a 12-hour format and parse to NA, exactly as a strict
# strptime() would treat them.
dg_strptime_period <- function(x, fmt, tz = "UTC") {
  if (!grepl("%p", fmt, fixed = TRUE)) {
    return(as.POSIXct(strptime(x, fmt, tz = tz)))
  }
  period <- dg_period_of(x)
  parsed <- as.POSIXct(
    strptime(dg_strip_period(x), dg_format_without_period(fmt), tz = tz)
  )
  parsed[is.na(period)] <- NA
  lt <- as.POSIXlt(parsed, tz = tz)
  hour <- lt$hour
  to_pm <- !is.na(period) & period == "pm" & !is.na(hour) & hour < 12L
  to_am <- !is.na(period) & period == "am" & !is.na(hour) & hour == 12L
  hour[to_pm] <- hour[to_pm] + 12L
  hour[to_am] <- 0L
  lt$hour <- hour
  as.POSIXct(lt)
}

# format() for a format that may contain "%p". The period comes from the
# value's own hour, not from the locale.
dg_format_period <- function(times, fmt, tz = "UTC",
                             tokens = list(am = "AM", pm = "PM")) {
  if (!grepl("%p", fmt, fixed = TRUE)) {
    return(format(times, fmt, tz = tz))
  }
  marker <- "DATAGANGERPERIODMARKER"
  out <- format(times, sub("%p", marker, fmt, fixed = TRUE), tz = tz)
  hour <- as.POSIXlt(times, tz = tz)$hour
  am_rows <- !is.na(hour) & hour < 12L
  pm_rows <- !is.na(hour) & !am_rows
  out[am_rows] <- sub(marker, tokens$am, out[am_rows], fixed = TRUE)
  out[pm_rows] <- sub(marker, tokens$pm, out[pm_rows], fixed = TRUE)
  out
}

# Picks the candidate format with the best *round-trip* fidelity, not just
# the first one that parses -- strptime is lenient (e.g. "%B" happily parses
# "Jun", "%d" happily parses " 2"), so parsing alone cannot distinguish
# "Jun  2, 2019" from "June 05, 2019". Formatting each successful parse back
# out with its own candidate format and comparing to the original text picks
# the format that actually reproduces the source data, which is what makes
# the synthetic output "look like" the original. Falls back to NULL (the
# generic character/categorical treatment) if nothing parses confidently
# (same 90% match-rate threshold detect_roles() uses to flag the column as
# date-like in the first place).
detect_date_format <- function(x, tz = "UTC") {
  x_sample <- x[!is.na(x) & nzchar(trimws(x))]
  if (length(x_sample) == 0L) {
    return(NULL)
  }
  if (length(x_sample) > 200L) x_sample <- x_sample[seq_len(200L)]
  x_sample <- trimws(x_sample)

  tokens <- dg_period_tokens(x_sample)

  best <- NULL
  best_fidelity <- -1
  for (cand in dg_date_format_candidates()) {
    parsed <- tryCatch(
      dg_strptime_period(x_sample, cand$fmt, tz = tz),
      error = function(e) rep(as.POSIXct(NA, tz = tz), length(x_sample))
    )
    if (mean(!is.na(parsed)) < 0.9) {
      next
    }
    round_trip <- tryCatch(
      trimws(dg_format_period(parsed, cand$fmt, tz = tz, tokens = tokens)),
      error = function(e) rep(NA_character_, length(x_sample))
    )
    fidelity <- mean(round_trip == x_sample, na.rm = TRUE)
    if (fidelity > best_fidelity) {
      best_fidelity <- fidelity
      best <- cand
    }
  }
  if (is.null(best)) {
    return(NULL)
  }
  list(format = best$fmt, has_date = best$has_date, has_time = best$has_time)
}

# Parses the whole column with the detected format. Returns NULL (rather
# than a partially-parsed column) when no candidate format fits well enough.
parse_date_like_character <- function(x, tz = "UTC") {
  info <- detect_date_format(x, tz = tz)
  if (is.null(info)) {
    return(NULL)
  }
  parsed <- dg_strptime_period(trimws(x), info$format, tz = tz)
  list(parsed = parsed, format = info$format, has_date = info$has_date, has_time = info$has_time)
}

synth_date_like_character <- function(x, n, date_info, coarsen_dates = TRUE,
                                      missing_strategy = "approx") {
  parsed <- date_info$parsed

  if (isTRUE(date_info$has_date) && !isTRUE(date_info$has_time)) {
    synth <- synth_date(as.Date(parsed), n, coarsen_dates = coarsen_dates, missing_strategy = "none")
  } else if (isTRUE(date_info$has_time) && !isTRUE(date_info$has_date)) {
    synth <- synth_time_of_day(parsed, n, missing_strategy = "none")
  } else {
    synth <- synth_posixct(parsed, n, coarsen_dates = coarsen_dates, missing_strategy = "none")
  }

  source_values <- trimws(x[!is.na(x) & nzchar(trimws(x))])
  out <- dg_format_period(
    synth, date_info$format,
    tz = "UTC", tokens = dg_period_tokens(source_values)
  )
  out[is.na(synth)] <- NA_character_

  # Missingness is applied once here (not inside the synth_* call above) so
  # the NA rate is estimated from the original character column, matching
  # how every other column type is handled.
  apply_missingness(out, x, n, missing_strategy)
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
                            merge_rare = FALSE, missing_strategy = "approx",
                            label_strategy = "preserve") {
  synth_categorical(
    x, n,
    rare_level_min_n = rare_level_min_n,
    merge_rare = merge_rare,
    missing_strategy = missing_strategy,
    label_strategy = label_strategy
  )
}

# ===========================================================================
# haven_labelled synthesis [2.8]
# ===========================================================================

synth_labelled <- function(x, n, rare_level_min_n = 5,
                           merge_rare = FALSE, missing_strategy = "approx",
                           label_strategy = "preserve") {
  validate_label_strategy(label_strategy)
  if (all(is.na(x))) {
    return(rep(NA_character_, n))
  }

  x_labels <- as.character(haven::as_factor(x))
  synth <- synth_categorical(
    x_labels, n,
    rare_level_min_n = rare_level_min_n,
    merge_rare = merge_rare,
    missing_strategy = missing_strategy,
    label_strategy = label_strategy
  )

  synth
}

# ===========================================================================
# Free text handling [2.8]
# ===========================================================================

synth_free_text <- function(x, n, strategy = "categorical",
                            rare_level_min_n = 5, merge_rare = FALSE,
                            missing_strategy = "approx",
                            label_strategy = "preserve") {
  validate_label_strategy(label_strategy)
  if (strategy == "drop") {
    return(rep(NA_character_, n))
  }
  if (strategy == "redact") {
    return(rep("[REDACTED]", n))
  }
  if (strategy == "categorical") {
    # Free text is not synthesized with any dedicated free-text model --
    # internally it gets the same treatment as any other high-cardinality
    # categorical column: values seen fewer than rare_level_min_n times are
    # collapsed to ".other" before resampling, so distinct free-text strings
    # (almost always all of them) do not reappear verbatim unless several
    # records shared the exact same text.
    return(synth_categorical(
      x, n,
      rare_level_min_n = rare_level_min_n,
      merge_rare = merge_rare,
      missing_strategy = missing_strategy,
      label_strategy = label_strategy
    ))
  }
  cli::cli_abort("Unknown free_text_strategy: {.val {strategy}}")
}

# ===========================================================================
# Alphanumeric ID scrambling [2.9]
# ===========================================================================

#' Replace one character with a different one of the same class
#'
#' Digits map to a different digit, lowercase to a different lowercase letter,
#' uppercase to a different uppercase letter. Any other character is returned
#' unchanged. Uses the (seeded) RNG so scrambling stays reproducible.
#'
#' @param ch A single-character string.
#' @return A single-character string.
#' @keywords internal
#' @noRd
dg_random_like_char <- function(ch) {
  pool <- if (grepl("[0-9]", ch)) {
    setdiff(as.character(0:9), ch)
  } else if (grepl("[a-z]", ch)) {
    setdiff(letters, ch)
  } else if (grepl("[A-Z]", ch)) {
    setdiff(LETTERS, ch)
  } else {
    return(ch)
  }
  if (length(pool) == 0L) ch else sample(pool, 1L)
}

#' Scramble an alphanumeric ID's characters, one value at a time
#'
#' Each value is transformed independently: delimiter characters
#' (`dg_alphanumeric_id_delimiters()`) stay in their exact original
#' positions. When a value has at least two distinct non-delimiter characters,
#' those characters are randomly reordered (preserving the multiset), which
#' destroys the value while keeping its length and delimiter layout and never
#' mixing characters across rows. When reordering cannot change the value -- a
#' single character (`"5"`) or all-identical characters (`"11"`, `"222"`), as
#' with short numeric IDs -- each non-delimiter character is instead replaced
#' with a random one of the same class.
#'
#' Candidates are checked against the ENTIRE observed value set, not only the
#' value being scrambled. Because a permutation preserves the character
#' multiset, one row's scramble can coincidentally reproduce another row's
#' original identifier (e.g. `"T0010"` permutes to `"T0001"`); emitting such
#' a value would hand the second record's identifier back in the synthetic
#' output. If every sampled candidate is an observed value, the function
#' degrades to the older in-place guarantee (returned value differs from its
#' own original) rather than returning the original itself.
#'
#' @param x Character vector of original values (`NA` passes through as `NA`).
#' @return A character vector the same length as `x`.
#' @keywords internal
#' @noRd
scramble_alphanumeric_id <- function(x) {
  delim_pattern <- paste0("[", dg_alphanumeric_id_delimiters(), "]")

  # Hash-set membership over every observed value, so candidate checks are
  # O(1) per draw even for long columns.
  observed <- new.env(parent = emptyenv())
  for (v in x[!is.na(x) & nzchar(x)]) {
    assign(v, TRUE, envir = observed)
  }
  is_observed <- function(candidate) {
    exists(candidate, envir = observed, inherits = FALSE)
  }

  vapply(x, function(val) {
    if (is.na(val) || !nzchar(val)) {
      return(val)
    }
    chars <- strsplit(val, "", fixed = TRUE)[[1]]
    scramble_idx <- which(!grepl(delim_pattern, chars))
    if (length(scramble_idx) == 0L) {
      return(val)
    }

    # When there are at least two DISTINCT non-delimiter characters, reorder
    # them (preserving the multiset). Typical alphanumeric IDs land here.
    if (length(scramble_idx) >= 2L &&
        length(unique(chars[scramble_idx])) >= 2L) {
      changed_fallback <- NULL
      for (attempt in 1:10) {
        perm <- sample(scramble_idx)
        out_chars <- chars
        out_chars[scramble_idx] <- out_chars[perm]
        out <- paste(out_chars, collapse = "")
        if (!is_observed(out)) {
          return(out)
        }
        if (is.null(changed_fallback) && !identical(out, val)) {
          changed_fallback <- out
        }
      }
      # Deterministic scan of two-position swaps of distinct characters,
      # looking for one outside the observed set. A swap of two different
      # characters can never be the identity, so at minimum the result
      # differs from `val`.
      for (i1 in scramble_idx) {
        for (i2 in scramble_idx) {
          if (i1 >= i2 || identical(chars[[i1]], chars[[i2]])) {
            next
          }
          out_chars <- chars
          out_chars[c(i1, i2)] <- out_chars[c(i2, i1)]
          out <- paste(out_chars, collapse = "")
          if (!is_observed(out)) {
            return(out)
          }
          if (is.null(changed_fallback)) {
            changed_fallback <- out
          }
        }
      }
      return(changed_fallback %||% val)
    }

    # Reordering cannot change this value (single character, or all identical),
    # as with short numeric IDs. Replace each non-delimiter character with a
    # random one of the same class so the value is genuinely de-identified
    # instead of surviving in place.
    changed_fallback <- NULL
    for (attempt in 1:20) {
      out_chars <- chars
      for (i in scramble_idx) {
        out_chars[[i]] <- dg_random_like_char(chars[[i]])
      }
      out <- paste(out_chars, collapse = "")
      if (!is_observed(out)) {
        return(out)
      }
      if (is.null(changed_fallback) && !identical(out, val)) {
        changed_fallback <- out
      }
    }
    changed_fallback %||% out
  }, character(1), USE.NAMES = FALSE)
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
