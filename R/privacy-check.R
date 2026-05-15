#' Run disclosure-risk privacy checks
#'
#' Scans original and (optionally) synthetic data for disclosure-risk flags.
#' Supports two stages: `"pre"` (before synthesis, requires only the
#' original dataset and roles) and `"post"` (after synthesis, requires both
#' original and synthetic).
#'
#' @param original The original data frame.
#' @param synthetic Optional; the synthetic data frame (required for
#'   `stage = "post"`).
#' @param roles Optional; a `dataganger_roles` object from [detect_roles()].
#'   Required for pre-stage flag detection.
#' @param stage Character. `"pre"` or `"post"`.
#' @param spec Optional; a `dataganger_spec` object. When provided at
#'   `stage = "post"`, cross-checks that synthesis parameters were applied
#'   (e.g. date coarsening, ID removal).
#'
#' @return An S3 object of class `dataganger_privacy_check`, a tibble with
#'   columns `variable`, `flag`, `severity`, `stage`, and `recommendation`.
#' @export
#'
#' @examples
#' df <- data.frame(id = 1:50, x = rnorm(50), city = rep("Toronto", 50))
#' roles <- detect_roles(df)
#' privacy_check(df, roles = roles, stage = "pre")
privacy_check <- function(original, synthetic = NULL, roles = NULL,
                          stage = c("pre", "post"), spec = NULL) {
  stage <- match.arg(stage)

  if (!is.data.frame(original)) {
    cli::cli_abort("{.arg original} must be a data frame")
  }

  if (stage == "post") {
    if (is.null(synthetic) || !is.data.frame(synthetic)) {
      cli::cli_abort("{.arg synthetic} must be a data frame for {.code stage = \"post\"}")
    }
  }

  if (stage == "pre") {
    flags <- privacy_check_pre(original, roles)
    attr(flags, "exact_row_matches") <- 0L
  } else {
    flags <- privacy_check_post(original, synthetic, roles, spec)
  }

  attr(flags, "stage")   <- stage
  attr(flags, "n_flags") <- nrow(flags)
  class(flags) <- c("dataganger_privacy_check", class(flags))

  flags
}

# ===========================================================================
# Pre-stage flags [3.6]
# ===========================================================================

privacy_check_pre <- function(original, roles) {
  flags <- list()

  # Build role lookup from roles object if available
  role_map <- NULL
  sensitive_map <- NULL
  if (!is.null(roles) && "variable" %in% names(roles)) {
    if ("recommended_role" %in% names(roles)) {
      role_map <- stats::setNames(roles$recommended_role, roles$variable)
    }
    if ("sensitive" %in% names(roles)) {
      sensitive_map <- stats::setNames(roles$sensitive, roles$variable)
    }
  }

  for (nm in names(original)) {
    x <- original[[nm]]
    role <- role_map[[nm]] %||% "unknown"
    sensitive <- isTRUE(sensitive_map[[nm]])

    # ID columns → HIGH
    if (role == "ID candidate" || grepl("(?i)^id$|_id$|^subject|^patient|^record|^case_no", nm, perl = TRUE)) {
      flags[[length(flags) + 1]] <- make_flag(nm, "ID column detected", "HIGH",
        "Review whether this column should be excluded from synthetic output")
      next
    }

    # Sensitive columns → MEDIUM
    if (sensitive && role != "ID candidate") {
      flags[[length(flags) + 1]] <- make_flag(nm, "Sensitive column detected", "MEDIUM",
        "Review whether this column should be coarsened or excluded")
    }

    # Free-text detection → MEDIUM
    if (is.character(x) && !all(is.na(x))) {
      x_obs <- x[!is.na(x)]
      mean_nchar <- mean(nchar(as.character(x_obs)))
      n_dist <- length(unique(x_obs))
      if (mean_nchar > 50 && n_dist > length(x) * 0.5) {
        flags[[length(flags) + 1]] <- make_flag(nm, "Free-text column detected", "MEDIUM",
          "Free-text columns can contain identifying information; consider exclusion")
      }
    }

    # Date columns with day precision → LOW
    if (inherits(x, "Date") || inherits(x, "POSIXct")) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Date column detected", "LOW",
        "Consider coarsening dates to reduce disclosure risk")
    }

    # Geography columns → LOW
    geo_pattern <- "(?i)(zip|postal|fsa|county|region|province|state|city|geo|lat|lon|coord)"
    if (grepl(geo_pattern, nm, perl = TRUE)) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Geography column detected", "LOW",
        "Geography columns can be re-identifying; consider coarsening or aggregation")
    }
  }

  if (length(flags) == 0) {
    return(tibble::tibble(
      variable       = character(0),
      flag           = character(0),
      severity       = character(0),
      recommendation = character(0)
    ))
  }

  dplyr::bind_rows(flags)
}

# ===========================================================================
# Post-stage flags [3.7]
# ===========================================================================

privacy_check_post <- function(original, synthetic, roles, spec) {
  flags <- list()
  exact_row_matches <- 0L

  role_map <- NULL
  if (!is.null(roles) && "variable" %in% names(roles) &&
      "recommended_role" %in% names(roles)) {
    role_map <- stats::setNames(roles$recommended_role, roles$variable)
  }

  # 1. ID columns still present in synthetic
  for (nm in intersect(names(original), names(synthetic))) {
    role <- role_map[[nm]] %||% "unknown"
    if (role == "ID candidate") {
      id_vals <- synthetic[[nm]]
      if (!all(is.na(id_vals))) {
        flags[[length(flags) + 1]] <- make_flag(nm,
          "ID column not fully masked in synthetic output", "HIGH",
          "ID columns should be fully masked (all-NA) in synthetic data")
      }
    }
  }

  # 2. Exact-row match check (C8: nrow >= 20 only)
  if (nrow(original) >= 20) {
    exact_row_matches <- exact_row_match_count(original, synthetic, role_map)
    if (exact_row_matches > 0) {
      flags[[length(flags) + 1]] <- make_flag("(dataset)",
          sprintf("%d exact-row match(es) between synthetic and original", exact_row_matches),
          "HIGH",
          "Exact-row matches increase disclosure risk; consider re-synthesizing with different seed or settings")
    }
  }

  # 3. Rare-category survival
  if (!is.null(spec)) {
    rare_min_n <- spec$rare_level_min_n %||% 5
  } else {
    rare_min_n <- 5
  }

  cat_cols <- names(original)[vapply(original, function(x) {
    is.character(x) || is.factor(x) || is.logical(x)
  }, logical(1))]
  cat_cols <- intersect(cat_cols, names(synthetic))

  for (nm in cat_cols) {
    x_orig <- as.character(original[[nm]])
    x_syn  <- as.character(synthetic[[nm]])
    tx <- table(x_orig[!is.na(x_orig)])
    rare_vals <- names(tx)[tx < rare_min_n & tx > 0]
    if (length(rare_vals) > 0) {
      survived <- rare_vals[rare_vals %in% x_syn[!is.na(x_syn)]]
      if (length(survived) > 0) {
        flags[[length(flags) + 1]] <- make_flag(nm,
          sprintf("Rare categories survived synthesis: %s", paste(survived, collapse = ", ")),
          "MEDIUM",
          "Rare categories may be identifying; verify they are safe to release")
      }
    }
  }

  # 4. Date precision not coarsened
  if (!is.null(spec) && isTRUE(spec$coarsen_dates)) {
    date_cols <- names(original)[vapply(original, function(x) {
      inherits(x, "Date") || inherits(x, "POSIXct")
    }, logical(1))]
    date_cols <- intersect(date_cols, names(synthetic))
    for (nm in date_cols) {
      if (inherits(synthetic[[nm]], "Date")) {
        days <- unique(format(synthetic[[nm]], "%d"))
        days <- days[!is.na(days)]
        if (length(days) > 1 && !all(days == "01")) {
          flags[[length(flags) + 1]] <- make_flag(nm,
            "Date column retains day-level precision despite coarsen_dates = TRUE",
            "MEDIUM",
            "Check that date coarsening was properly applied during synthesis")
        }
      }
    }
  }

  if (length(flags) == 0) {
    out <- tibble::tibble(
      variable       = character(0),
      flag           = character(0),
      severity       = character(0),
      recommendation = character(0)
    )
    attr(out, "exact_row_matches") <- exact_row_matches
    return(out)
  }

  out <- dplyr::bind_rows(flags)
  attr(out, "exact_row_matches") <- exact_row_matches
  out
}

# ===========================================================================
# Helpers
# ===========================================================================

make_flag <- function(variable, flag, severity, recommendation) {
  tibble::tibble(
    variable       = variable,
    flag           = flag,
    severity       = severity,
    recommendation = recommendation
  )
}

exact_row_match_count <- function(original, synthetic, role_map = NULL) {
  if (nrow(original) < 20 || nrow(synthetic) == 0) {
    return(0L)
  }

  common_cols <- intersect(names(original), names(synthetic))
  id_cols <- character(0)
  if (!is.null(role_map)) {
    id_cols <- names(role_map)[role_map == "ID candidate"]
  }
  match_cols <- setdiff(common_cols, id_cols)

  if (length(match_cols) == 0) {
    return(0L)
  }

  orig_key <- row_key(original[, match_cols, drop = FALSE])
  syn_key <- row_key(synthetic[, match_cols, drop = FALSE])
  as.integer(sum(syn_key %in% orig_key, na.rm = TRUE))
}

# ===========================================================================
# Print method [3.8]
# ===========================================================================

#' @export
print.dataganger_privacy_check <- function(x, ...) {
  cli::cli_h1("DataGangeR Privacy Check ({attr(x, \"stage\")} stage)")

  if (nrow(x) == 0) {
    cli::cli_alert_success("No flags raised.")
    return(invisible(x))
  }

  sevs <- c("HIGH", "MEDIUM", "LOW")
  for (s in sevs) {
    rows <- x[x$severity == s, ]
    if (nrow(rows) == 0) next

    icon <- switch(s, HIGH = "x", MEDIUM = "!", LOW = "i")
    header <- sprintf("%s %s severity (%d)", icon, s, nrow(rows))
    cli::cli_h2(header)

    for (i in seq_len(nrow(rows))) {
      r <- rows[i, ]
      cli::cli_li("{.field {r$variable}}: {r$flag}")
      cli::cli_text("  {.emph Recommendation}: {r$recommendation}")
    }
  }

  invisible(x)
}
