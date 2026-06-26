#' Detect data roles for each column
#'
#' Applies heuristic-based role detection to every column in a data frame.
#' Roles include ID candidate, date, label_check (labelled vectors),
#' categorical candidate, free text, geography, and unknown. All assignments
#' are overridable by passing a `user_role` column in a supplied roles tibble.
#'
#' @param data A data frame.
#' @param profile Optional; a `dataganger_profile` object from
#'   [profile_data()]. If `NULL` (the default), profiling is performed
#'   internally.
#'
#' @return An S3 object of class `dataganger_roles`, a tibble with columns:
#'   \describe{
#'     \item{variable}{Column name.}
#'     \item{class}{R class of the column.}
#'     \item{recommended_role}{Role detected by heuristic.}
#'     \item{user_role}{User-supplied override (initially `NA`).}
#'     \item{simulation}{How the column is treated during synthesis.}
#'     \item{reason}{Justification for the recommended role.}
#'     \item{disclosure_role}{Disclosure role. `NA` (unselected) is the
#'       conservative default whenever detection is not confident; the user must
#'       choose a role before generating. `"direct"` and `"sensitive"` are the
#'       only values auto-assigned (confident identifier / known-sensitive name).
#'       `"quasi"` and `"none"` are user-assigned choices only.}
#'     \item{disclosure_reason}{Justification for the auto-assigned disclosure role.}
#'   }
#' @export
#'
#' @examples
#' df <- data.frame(
#'   id   = 1:50,
#'   date = as.Date("2020-01-01") + 0:49,
#'   city = rep(c("Toronto", "Vancouver", "Montreal"), length.out = 50),
#'   cat  = factor(rep(letters[1:3], length.out = 50))
#' )
#' detect_roles(df)
detect_roles <- function(data, profile = NULL) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame, not {.obj_type_friendly {data}}")
  }

  n_rows <- nrow(data)

  roles <- vector("list", ncol(data))
  names(roles) <- names(data)

  for (i in seq_len(ncol(data))) {
    col_name <- names(data)[i]
    x <- data[[i]]
    roles[[i]] <- detect_single_role(x, col_name, n_rows)
  }

  out <- dplyr::bind_rows(roles)

  class(out) <- c("dataganger_roles", class(out))
  out
}

# ---------------------------------------------------------------------------
# Single-column role detector — implements threshold table verbatim
# ---------------------------------------------------------------------------

# Conservative known-sensitive column-name heuristic. Documented in
# inst/disclosure-sensitive-terms.md for review. Intentionally narrow:
# a missed sensitive column is recoverable at the Configure gate (the user must
# choose a role for every column), while a false positive is annoying. Keep tight.
is_sensitive_name <- function(name) {
  rx <- paste0(
    "(?i)(diagnos|\\bicd\\b|disease|\\bcondition|symptom|",
    "\\brace|ethnic|religio|sexual|orientation|gender_identity|",
    "\\bhiv\\b|\\bsti\\b|\\bstd\\b|mental_health|disabilit|",
    "income|salary|\\bwage|earnings|criminal|conviction|immigration)"
  )
  grepl(rx, name, perl = TRUE)
}

detect_single_role_inner <- function(x, name, n_rows) {
  # Determine class for the output
  if (haven::is.labelled(x)) {
    r_class <- "haven_labelled"
  } else if (inherits(x, "Date")) {
    r_class <- "Date"
  } else if (inherits(x, "POSIXct")) {
    r_class <- "POSIXct"
  } else if (is.factor(x)) {
    r_class <- "factor"
  } else if (is.numeric(x)) {
    r_class <- "numeric"
  } else if (is.character(x)) {
    r_class <- "character"
  } else if (is.logical(x)) {
    r_class <- "logical"
  } else {
    r_class <- class(x)[1]
  }

  # Compute n_distinct safely (avoiding base R dist fn issues with labelled)
  if (haven::is.labelled(x)) {
    x_for_distinct <- haven::as_factor(x)
  } else {
    x_for_distinct <- x
  }
  n_distinct <- length(unique(x_for_distinct[!is.na(x_for_distinct)]))

  # --- Threshold tests in order ---

  # Test 1: haven_labelled
  if (r_class == "haven_labelled") {
    return(make_role_row(name, r_class, "label_check", "class is haven_labelled", NA_character_))
  }

  # Test 2: Date or POSIXct
  if (r_class %in% c("Date", "POSIXct")) {
    return(make_role_row(name, r_class, "date", "class is Date or POSIXct", NA_character_))
  }

  # Test 2b: character column storing dates as formatted strings.
  # Catches date strings that are not native Date/POSIXct (e.g. "Jun 8, 2019",
  # "2020-01-15", "01/08/2020"). Checked before free-text so short date strings
  # are not misclassified as free text by the word-count heuristic.
  if (r_class == "character") {
    x_sample <- x[!is.na(x) & nzchar(trimws(x))]
    if (length(x_sample) > 200L) x_sample <- x_sample[seq_len(200L)]
    if (length(x_sample) >= 5L) {
      date_rx <- paste0(
        "^(\\d{4}-\\d{2}-\\d{2}",                   # ISO: 2020-01-15
        "|[A-Z][a-z]{2}\\s+\\d{1,2},?\\s*\\d{4}",   # "Jun 8, 2019" / "Jun 8 2019"
        "|\\d{1,2}/\\d{1,2}/\\d{2,4}",              # MM/DD/YY or MM/DD/YYYY
        "|\\d{4}/\\d{2}/\\d{2})"                    # YYYY/MM/DD
      )
      if (mean(grepl(date_rx, trimws(x_sample))) >= 0.9) {
        return(make_role_row(
          name, r_class, "date",
          "character values match a common date string format",
          NA_character_
        ))
      }
    }
  }

  # Test 3: free text
  if (is_free_text_candidate(x)) {
    return(make_role_row(
      name,
      r_class,
      "free text",
      "median string length > 20 or median word count >= 5",
      "direct"
    ))
  }

  # Test 4: geography column name pattern
  geo_pattern <- "(?i)(zip|postal|fsa|county|region|province|state|city|geo|lat|lon|coord)"
  if (grepl(geo_pattern, name, perl = TRUE)) {
    return(make_role_row(name, r_class, "geography", paste0("name matches geography pattern: ", geo_pattern), NA_character_))
  }

  # Test 5: name matches ID patterns
  id_pattern <- "(?i)(^id$|_id$|^subject|^patient|^record|^case(_no)?$|uuid|guid|(^|_)(key|code|num|no)$)"
  if (grepl(id_pattern, name, perl = TRUE)) {
    return(make_role_row(name, r_class, "ID candidate", paste0("name matches ID pattern: ", id_pattern), "direct"))
  }

  # Test 6: high cardinality → ID candidate
  # Guard: character columns with long median values are not IDs even when
  # unique — they belong in free text territory and only reached here due to
  # edge cases in is_free_text_candidate (e.g. non-sentence long strings).
  # Numeric columns are excluded: distinctive numbers (lab values, prices,
  # measurements) are not identifiers unless the column name says so (Test 5).
  # They fall through to the numeric rule below for the user to classify in
  # the UI — DataGangeR is designed for the user to make that call.
  distinct_ratio <- if (n_rows > 0) n_distinct / n_rows else 0
  is_long_char <- is.character(x) && {
    x_obs <- x[!is.na(x) & nzchar(trimws(x))]
    length(x_obs) > 0 && stats::median(nchar(x_obs), na.rm = TRUE) > 20
  }
  if (!is_long_char && !is.numeric(x) && distinct_ratio >= 0.95 && n_rows >= 20 && !all(is.na(x))) {
    return(make_role_row(name, r_class, "ID candidate", "n_distinct/nrow >= 0.95", "direct"))
  }

  # Test 7: low cardinality → categorical candidate
  if (distinct_ratio < 0.05 || n_distinct <= 20) {
    return(make_role_row(name, r_class, "categorical candidate", "n_distinct/nrow < 0.05 or n_distinct <= 20", NA_character_))
  }

  # Test 8: distinctive numeric → numeric (user classifies via UI)
  if (is.numeric(x)) {
    return(make_role_row(name, r_class, "numeric", "distinctive numeric; classify via UI", NA_character_))
  }

  # Default
  make_role_row(name, r_class, "unknown", "no rule matched", NA_character_)
}

detect_single_role <- function(x, name, n_rows) {
  row <- detect_single_role_inner(x, name, n_rows)
  # Sensitive name heuristic: a known-sensitive column is marked sensitive
  # unless it is already a confident direct identifier (direct wins — it is
  # removed from output entirely, the stronger protection).
  if (is_sensitive_name(name) && !identical(row$disclosure_role, "direct")) {
    row$disclosure_role <- "sensitive"
    row$disclosure_reason <- "auto: column name matches a known-sensitive pattern"
  }
  row
}

is_free_text_candidate <- function(x) {
  if (!is.character(x) || all(is.na(x))) {
    return(FALSE)
  }

  x_obs <- trimws(x[!is.na(x)])
  x_obs <- x_obs[nzchar(x_obs)]
  if (length(x_obs) == 0) {
    return(FALSE)
  }

  # Free-text detection is a heuristic; the per-row strsplit below is the hot
  # path on long character columns at the Configure transition. A fixed,
  # deterministic head-sample is plenty for a median statistic and keeps this
  # bounded in the number of rows. Deterministic (not random) so role detection
  # stays reproducible and never touches the user's RNG stream.
  if (length(x_obs) > 1000L) {
    x_obs <- x_obs[seq_len(1000L)]
  }

  median_nchar <- stats::median(nchar(x_obs), na.rm = TRUE)
  word_counts <- vapply(strsplit(x_obs, "\\s+"), length, integer(1))
  median_word_count <- stats::median(word_counts, na.rm = TRUE)

  isTRUE(median_nchar > 20 || median_word_count >= 5)
}

make_role_row <- function(name, r_class, role, reason, disclosure_role) {
  tibble::tibble(
    variable         = name,
    class            = r_class,
    recommended_role = role,
    user_role        = NA_character_,
    simulation       = "synthesize",
    reason           = reason,
    disclosure_role = disclosure_role,
    disclosure_reason = disclosure_reason_for(disclosure_role, role)
  )
}

disclosure_reason_for <- function(disclosure_role, role) {
  if (is.na(disclosure_role)) {
    return("auto: not confidently identifying; choose a disclosure role before generating")
  }
  switch(disclosure_role,
    direct = "auto: identifies a person by itself; removed from output",
    sensitive = "auto: column name matches a known-sensitive pattern",
    quasi = "user: identifying in combination; covered by the k-anonymity guarantee",
    none = "user: not identifying alone or in combination",
    "auto"
  )
}

# ---------------------------------------------------------------------------
# Print method
# ---------------------------------------------------------------------------

#' @export
print.dataganger_roles <- function(x, ...) {
  cli::cli_h1("DataGangeR Roles")

  n_overrides <- sum(!is.na(x$user_role))
  n_total <- nrow(x)

  cli::cli_text("{.val {n_total}} column{?s} analysed; {.val {n_overrides}} user override{?s} active")
  cli::cli_text("")

  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    # Use [[]] for scalar extraction from a single-row tibble to avoid
    # length-0 returns on NA columns that can trip if() in older tibble versions.
    user_role_val <- r[["user_role"]]
    role <- if (!is.na(user_role_val) && nzchar(user_role_val))
      user_role_val else r[["recommended_role"]]
    override <- !is.na(user_role_val) && nzchar(user_role_val)

    header <- sprintf("%s (%s) -> %s", r$variable, r$class, role)
    if (override) {
      header <- paste0(header, " ", cli::col_yellow("[user override]"))
    }

    cli::cli_h3(header)
    cli::cli_li("Reason: {r$reason}")
    if (!is.na(r$disclosure_role) && r$disclosure_role != "none") {
      cli::cli_li("{.strong Disclosure}: {r$disclosure_role}")
    }
  }

  cli::cli_text("")
  if (n_overrides > 0) {
    cli::cli_alert_info("User overrides are active; re-run {.fun detect_roles} to reset")
  }

  invisible(x)
}
