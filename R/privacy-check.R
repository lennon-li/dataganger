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
#'   Recommended for pre-stage flag detection. When omitted, fallback name/type heuristics are used.
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
    flags <- augment_synthpop_disclosure(flags, original, synthetic, roles)
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
  disclosure_map <- NULL
  if (!is.null(roles) && "variable" %in% names(roles)) {
    if ("recommended_role" %in% names(roles)) {
      role_map <- stats::setNames(roles$recommended_role, roles$variable)
    }
    if ("disclosure_role" %in% names(roles)) {
      disclosure_map <- stats::setNames(roles$disclosure_role, roles$variable)
    }
  }

  for (nm in names(original)) {
    x <- original[[nm]]
    role <- role_map[[nm]] %||% "unknown"
    disclosure <- disclosure_map[[nm]] %||% "none"

    # ID columns -> HIGH
    if (role == "ID candidate" || grepl("(?i)^id$|_id$|^subject|^patient|^record|^case_no", nm, perl = TRUE)) {
      flags[[length(flags) + 1]] <- make_flag(nm, "ID column detected", "HIGH",
        "Review whether this column should be excluded from synthetic output")
      next
    }

    # Direct identifier -> HIGH
    if (identical(disclosure, "direct")) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Direct identifier", "HIGH",
        "Direct identifiers are removed from synthetic output")
      next
    }

    # Sensitive target -> MEDIUM (informational; not yet enforced)
    if (identical(disclosure, "sensitive")) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Sensitive target", "MEDIUM",
        "Kept for analysis; attribute-disclosure protection is not yet applied")
    }

    # Free-text detection -> MEDIUM
    if (is.character(x) && !all(is.na(x))) {
      x_obs <- x[!is.na(x)]
      mean_nchar <- mean(nchar(as.character(x_obs)))
      n_dist <- length(unique(x_obs))
      if (mean_nchar > 50 && n_dist > length(x) * 0.5) {
        flags[[length(flags) + 1]] <- make_flag(nm, "Free-text column detected", "MEDIUM",
          "Free-text columns can contain identifying information; consider exclusion")
      }
    }

    # Date columns with day precision -> LOW
    if (inherits(x, "Date") || inherits(x, "POSIXct")) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Date column detected", "LOW",
        "Consider coarsening dates to reduce disclosure risk")
    }

    # Geography columns -> LOW
    geo_pattern <- "(?i)(zip|postal|fsa|county|region|province|state|city|geo|lat|lon|coord)"
    if (grepl(geo_pattern, nm, perl = TRUE)) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Geography column detected", "LOW",
        "Geography columns can be re-identifying; consider coarsening or aggregation")
    }
  }

  if (!is.null(disclosure_map)) {
    qi_cols <- names(disclosure_map)[disclosure_map == "quasi"]
    qi_cols <- intersect(qi_cols, names(original))
    if (length(qi_cols) >= 1L) {
      res <- assess_kanonymity(original, qi_cols, k = 5)
      if (!isTRUE(res$no_qi) && !is.na(res$smallest_cell) && res$n_below > 0L) {
        flags[[length(flags) + 1]] <- make_flag(
          "(quasi-identifiers)",
          sprintf(
            "%d record(s) (%.1f%%) in QI combinations smaller than k=5; smallest cell = %d",
            res$n_below, res$pct_below, res$smallest_cell
          ),
          "HIGH",
          "These combinations are re-identifying; synthesis will coarsen or suppress them"
        )
      }
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

  dr <- NULL
  if (!is.null(roles) && "disclosure_role" %in% names(roles)) {
    dr <- stats::setNames(roles$disclosure_role, roles$variable)
  }
  if (!is.null(dr)) {
    k_target <- if (!is.null(spec)) spec$k_anon %||% 5 else 5
    qi_cols <- intersect(names(dr)[dr %in% "quasi"], names(synthetic))  # %in% is NA-safe
    if (length(qi_cols) >= 1L) {
      res <- assess_kanonymity(synthetic, qi_cols, k = k_target)
      if (!is.na(res$smallest_cell) && res$smallest_cell < k_target) {
        flags[[length(flags) + 1]] <- make_flag(
          "(quasi-identifiers)",
          sprintf(
            "Synthetic output has a QI cell of size %d (< k=%d)",
            res$smallest_cell, k_target
          ),
          "HIGH",
          "k-anonymity enforcement did not reach the target; review enforce_kanon settings"
        )
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

augment_synthpop_disclosure <- function(flags, original, synthetic, roles) {
  if (!identical(attr(synthetic, "engine", exact = TRUE), "synthpop")) {
    return(flags)
  }

  disclosure <- synthpop_disclosure_panel(original, synthetic, roles)
  if (is.null(disclosure)) {
    return(flags)
  }

  rows <- synthpop_disclosure_flags(disclosure)
  if (nrow(rows) > 0L) {
    flags <- dplyr::bind_rows(flags, rows)
  }
  attr(flags, "synthpop_disclosure") <- disclosure
  flags
}

synthpop_disclosure_panel <- function(original, synthetic, roles) {
  if (!requireNamespace("synthpop", quietly = TRUE)) {
    return(NULL)
  }

  qi_cols <- synthpop_disclosure_cols(roles)
  qi_cols <- intersect(qi_cols, intersect(names(original), names(synthetic)))
  if (length(qi_cols) < 2L) {
    return(NULL)
  }

  target <- qi_cols[[length(qi_cols)]]
  keys <- setdiff(qi_cols, target)
  if (length(keys) == 0L) {
    return(NULL)
  }

  # synthpop::disclosure() does base `data[, j]` column extraction internally,
  # which returns sub-tibbles (not vectors) for tbl_df input and fails with
  # "cannot xtfrm data frames"; coerce to plain data.frame first.
  original_qi <- as.data.frame(original[, qi_cols, drop = FALSE])
  synthetic_qi <- as.data.frame(synthetic[, qi_cols, drop = FALSE])

  # Keep disclosure() scoped to role-flagged QI columns; sample rows later if
  # this is still too costly on very large data.
  result <- tryCatch(
    synthpop::disclosure(
      synthetic_qi,
      original_qi,
      keys = keys,
      target = target,
      print.flag = FALSE
    ),
    error = function(e) NULL
  )
  if (is.null(result)) {
    return(NULL)
  }

  list(
    keys = keys,
    target = target,
    identity_repu = disclosure_numeric(result$ident, "repU"),
    attribute_disco = disclosure_numeric(result$attrib, "DiSCO"),
    raw = result
  )
}

synthpop_disclosure_cols <- function(roles) {
  if (is.null(roles) || !"variable" %in% names(roles)) {
    return(character())
  }

  role <- if ("recommended_role" %in% names(roles)) {
    roles$recommended_role
  } else {
    rep(NA_character_, nrow(roles))
  }

  disclosure <- if ("disclosure_role" %in% names(roles)) {
    roles$disclosure_role
  } else {
    rep("none", nrow(roles))
  }

  roles$variable[
    role %in% c("ID candidate", "date", "categorical candidate", "label_check") |
      disclosure %in% c("quasi", "direct", "sensitive")
  ]
}

synthpop_disclosure_flags <- function(disclosure) {
  rows <- list()
  if (!is.na(disclosure$identity_repu)) {
    rows[[length(rows) + 1L]] <- make_flag(
      "(synthpop disclosure)",
      sprintf("Identity disclosure repU: %.2f", disclosure$identity_repu),
      "LOW",
      "Review synthpop disclosure metrics before sharing relationship-preserving synthetic data"
    )
  }
  if (!is.na(disclosure$attribute_disco)) {
    rows[[length(rows) + 1L]] <- make_flag(
      "(synthpop disclosure)",
      sprintf("Attribute disclosure DiSCO: %.2f", disclosure$attribute_disco),
      "LOW",
      "Review synthpop disclosure metrics before sharing relationship-preserving synthetic data"
    )
  }

  if (length(rows) == 0L) {
    return(tibble::tibble(
      variable       = character(0),
      flag           = character(0),
      severity       = character(0),
      recommendation = character(0)
    ))
  }

  dplyr::bind_rows(rows)
}

disclosure_numeric <- function(x, name) {
  if (is.null(x)) {
    return(NA_real_)
  }

  if (is.data.frame(x) || is.matrix(x)) {
    nms <- colnames(x)
    idx <- which(tolower(nms) == tolower(name))
    if (length(idx)) {
      return(as.numeric(x[1, idx[[1]]]))
    }
  }

  if (is.list(x) && !is.null(names(x))) {
    idx <- which(tolower(names(x)) == tolower(name))
    if (length(idx)) {
      return(as.numeric(x[[idx[[1]]]][[1]]))
    }
  }

  NA_real_
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
