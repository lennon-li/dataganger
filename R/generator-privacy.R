# Privacy checks for the trusted fitted-generator runtime.

generator_runtime_row_fingerprints <- function(data, key) {
  if (!is.data.frame(data) || !is.raw(key) || !nrow(data)) {
    return(character())
  }
  vapply(seq_len(nrow(data)), function(row) {
    generator_fit_row_fingerprint(data, row, key)
  }, character(1L))
}

generator_runtime_privacy_check <- function(synthetic, generator, roles) {
  index <- generator$exact_row_index
  exact_matches <- integer()
  exact_row_unavailable <- FALSE

  if (is.null(index) || !is.list(index)) {
    exact_row_unavailable <- TRUE
  } else if (!is.raw(index$key)) {
    exact_row_unavailable <- TRUE
  } else if (!is.character(index$fingerprints)) {
    exact_row_unavailable <- TRUE
  } else if (!"algorithm" %in% names(index) || !identical(index$algorithm, "HMAC-SHA256")) {
    exact_row_unavailable <- TRUE
  } else {
    fingerprints <- generator_runtime_row_fingerprints(synthetic, index$key)
    exact_matches <- which(fingerprints %in% index$fingerprints)
  }

  kanon <- attr(synthetic, "kanon", exact = TRUE)
  blockers <- list()
  if (exact_row_unavailable) {
    blockers[[length(blockers) + 1L]] <- generator_fit_issue(
      "exact_row_check_unavailable",
      "The exact-row privacy check could not be performed and the output is therefore not cleared. The generator must be re-frozen."
    )
  }
  if (length(exact_matches)) {
    blockers[[length(blockers) + 1L]] <- generator_fit_issue(
      "exact_row_match",
      "Generated output contains a complete row present in the private exact-row index."
    )
  }
  if (isTRUE(kanon$infeasible)) {
    blockers[[length(blockers) + 1L]] <- generator_fit_issue(
      "kanonymity_infeasible",
      "The requested k-anonymity target could not be applied without excessive suppression."
    )
  }

  list(
    ok = length(blockers) == 0L,
    blockers = generator_fit_issue_table(blockers),
    exact_matches = as.integer(exact_matches),
    exact_match_count = as.integer(length(exact_matches)),
    kanon = kanon %||% list(
      qi_cols = character(), k = NA_integer_, smallest_cell = NA_integer_,
      suppressed_cells = 0L, suppressed_rows = 0L,
      suppressed_row_frac = 0, infeasible = FALSE
    ),
    qi_cols = if (is.list(kanon)) kanon$qi_cols %||% character() else character()
  )
}

generator_runtime_roles <- function(generator) {
  roles <- generator$roles
  if (!is.list(roles) || is.null(names(roles)) || !length(roles)) {
    return(NULL)
  }
  result <- as.data.frame(roles, stringsAsFactors = FALSE, optional = TRUE)
  if ("sensitive" %in% names(result)) {
    result$sensitive <- as.logical(result$sensitive)
  }
  if ("identifies" %in% names(result)) {
    result$identifies <- as.character(result$identifies)
  }
  result
}

generator_runtime_summary_diagnostics <- function(synthetic, generator) {
  summaries <- vector("list", length(generator$columns))
  names(summaries) <- names(generator$columns)
  for (name in names(generator$columns)) {
    state <- generator$columns[[name]]
    value <- if (name %in% names(synthetic)) synthetic[[name]] else NULL
    if (is.null(value) || identical(state$kind, "dropped")) {
      summaries[[name]] <- list(kind = state$kind, present = FALSE)
      next
    }
    if (identical(state$kind, "numeric")) {
      observed <- as.numeric(value[!is.na(value)])
      summaries[[name]] <- list(
        kind = state$kind,
        present = TRUE,
        mean = if (length(observed)) mean(observed) else NA_real_,
        range = if (length(observed)) range(observed) else c(NA_real_, NA_real_),
        missing_rate = mean(is.na(value)),
        target_range = c(state$bounds$lower, state$bounds$upper)
      )
    } else if (identical(state$kind, "categorical")) {
      counts <- table(factor(as.character(value), levels = state$levels), useNA = "no")
      summaries[[name]] <- list(
        kind = state$kind,
        present = TRUE,
        levels = state$levels,
        probabilities = as.numeric(counts / max(1, sum(counts))),
        missing_rate = mean(is.na(value))
      )
    } else if (identical(state$kind, "logical")) {
      summaries[[name]] <- list(
        kind = state$kind,
        present = TRUE,
        true_probability = mean(value == TRUE, na.rm = TRUE),
        missing_rate = mean(is.na(value))
      )
    } else {
      summaries[[name]] <- list(
        kind = state$kind,
        present = TRUE,
        missing_rate = mean(is.na(value))
      )
    }
  }
  summaries
}
