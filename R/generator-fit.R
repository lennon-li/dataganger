fit_internal_generator <- function(data, spec, roles) {
  blockers <- list()
  warnings <- list()
  add_blocker <- function(code, message, column = NA_character_) {
    blockers[[length(blockers) + 1L]] <<- generator_fit_issue(code, message, column)
  }
  add_warning <- function(code, message, column = NA_character_) {
    warnings[[length(warnings) + 1L]] <<- generator_fit_issue(code, message, column)
  }

  if (!is.data.frame(data)) {
    add_blocker("invalid_data", "Input must be a plain data frame or tibble.")
  }
  if (is.data.frame(data) && (is.null(names(data)) || anyNA(names(data)) ||
    any(!nzchar(names(data))) || anyDuplicated(names(data)))) {
    add_blocker("invalid_column_names", "Input column names must be non-empty and unique.")
  }
  spec_valid <- inherits(spec, "dataganger_spec") && is.list(spec) &&
    !is.null(names(spec)) && !anyNA(names(spec)) &&
    !any(!nzchar(names(spec))) && !anyDuplicated(names(spec))
  if (!spec_valid) {
    add_blocker("invalid_spec", "Synthesis specification must be a valid dataganger_spec object.")
  }

  engine <- if (spec_valid) spec$engine %||% engine_from_correlations(spec) else NA_character_
  if (!is.character(engine) || length(engine) != 1L || is.na(engine) ||
    !engine %in% c("internal", "marginal")) {
    add_blocker("engine_ineligible", "V1 fitted generators require engine = \"internal\".")
  }
  missingness <- if (spec_valid) spec$preserve_missingness %||% "approx" else "approx"
  if (!is.character(missingness) || length(missingness) != 1L ||
    is.na(missingness) || !missingness %in% c("approx", "none")) {
    if (identical(missingness, "exact")) {
      add_blocker("exact_missingness", "Exact missingness is not eligible for a V1 fitted generator.")
    } else {
      add_blocker("invalid_missingness", "Missingness preservation must be approx or none.")
    }
  }
  if (spec_valid && any(c("constraints", "constraint", "custom_constraints") %in% names(spec))) {
    constraint_fields <- intersect(c("constraints", "constraint", "custom_constraints"), names(spec))
    if (any(!vapply(spec[constraint_fields], is.null, logical(1)))) {
      add_blocker("unsafe_constraints", "Constraints require separate validation before fitting.")
    }
  }

  roles_valid <- is.data.frame(data) && generator_fit_validate_roles(roles, data)
  if (!roles_valid) {
    add_blocker("roles_invalid", "Roles must be a complete dataganger_roles table in data-column order.")
  }
  if (!is.data.frame(data) || !roles_valid || !spec_valid) {
    report <- generator_fit_report(blockers, warnings)
    result <- structure(
      list(
        schema_version = generator_schema_version(),
        engine = "internal",
        eligible = FALSE,
        columns = list(),
        risk_report = report,
        roles = NULL,
        settings = NULL,
        exact_row_index = NULL
      ),
      class = "dataganger_generator"
    )
    validate_internal_generator(result)
    return(result)
  }

  rare_level_min_n <- spec$rare_level_min_n %||% 5L
  if (!is.numeric(rare_level_min_n) || length(rare_level_min_n) != 1L ||
    is.na(rare_level_min_n) || !is.finite(rare_level_min_n) ||
    rare_level_min_n <= 1 || rare_level_min_n > .Machine$integer.max ||
    rare_level_min_n != floor(rare_level_min_n)) {
    add_blocker("invalid_rare_threshold", "Rare-label threshold must be one finite number greater than one.")
    rare_level_min_n <- 5L
  }
  rare_level_min_n <- as.integer(rare_level_min_n)
  coarsen_dates <- spec$coarsen_dates %||% TRUE
  if (!is.logical(coarsen_dates) || length(coarsen_dates) != 1L ||
    is.na(coarsen_dates)) {
    add_blocker("invalid_date_coarsening", "Date coarsening must be one logical value.")
    coarsen_dates <- TRUE
  }
  coarsen_dates <- isTRUE(coarsen_dates)
  default_label_strategy <- spec$label_strategy %||% "preserve"
  if (!is.character(default_label_strategy) || length(default_label_strategy) != 1L ||
    is.na(default_label_strategy) || !default_label_strategy %in% c("preserve", "mask_rare")) {
    add_blocker("invalid_label_strategy", "Default label strategy must be preserve or mask_rare.")
    default_label_strategy <- "preserve"
  }
  merge_rare <- spec$merge_rare %||% FALSE
  if (!is.logical(merge_rare) || length(merge_rare) != 1L || is.na(merge_rare)) {
    add_blocker("invalid_rare_merge", "Rare-label merging must be one logical value.")
    merge_rare <- FALSE
  }
  merge_rare <- isTRUE(merge_rare)
  free_text_strategy <- spec$free_text_strategy %||% "categorical"
  if (!is.character(free_text_strategy) || length(free_text_strategy) != 1L ||
    is.na(free_text_strategy) || !free_text_strategy %in% c("categorical", "drop", "redact")) {
    add_blocker("invalid_free_text_strategy", "Free-text strategy must be categorical, drop, or redact.")
    free_text_strategy <- "categorical"
  }
  exact_row_key <- generator_fit_csprng_key()
  if (is.null(exact_row_key)) {
    add_blocker(
      "exact_row_key_unavailable",
      "A trusted cryptographic random key could not be obtained; exact-row protection is unavailable."
    )
  }
  columns <- vector("list", ncol(data))
  names(columns) <- names(data)

  for (i in seq_len(ncol(data))) {
    name <- names(data)[[i]]
    x <- data[[i]]
    role <- generator_fit_effective_role(roles, i)
    simulation <- generator_fit_role_value(roles, i, "simulation")
    label_strategy <- generator_fit_role_value(roles, i, "label_strategy", default_label_strategy)

    if (!simulation %in% c("synthesize", "drop", "pass_through", "scramble")) {
      add_blocker("unsafe_simulation", "Column has an unsupported simulation decision.", name)
      next
    }
    if (identical(simulation, "pass_through")) {
      add_blocker("pass_through", "Pass-through columns retain source rows and are ineligible.", name)
      next
    }
    if (identical(simulation, "scramble")) {
      add_blocker("scramble", "Scramble requires source values and is ineligible.", name)
      next
    }
    if (identical(simulation, "drop")) {
      columns[[i]] <- list(kind = "dropped", storage = "none")
      add_warning("column_dropped", "Column is approved for drop and no fitted values were retained.", name)
      next
    }
    if (role %in% c("free text", "free_text")) {
      if (free_text_strategy %in% c("drop", "redact")) {
        columns[[i]] <- list(kind = if (identical(free_text_strategy, "drop")) "dropped" else "redacted", storage = "none")
        add_warning("free_text_not_retained", "Free-text column is approved for non-retention.", name)
      } else {
        add_blocker("free_text_unsafe", "Free-text columns must be dropped or redacted before fitting.", name)
      }
      next
    }
    if (role %in% c("alphanumeric ID", "alphanumeric_id")) {
      add_blocker("direct_identifier", "Direct identifiers cannot be retained by the V1 fitted generator.", name)
      next
    }
    if (!generator_fit_supported_column(x)) {
      add_blocker("unsupported_class", "Column class is not supported by the V1 internal compiler.", name)
      next
    }
    if (identical(role, "postal code") || identical(role, "postal_code")) {
      country <- generator_fit_role_value(roles, i, "postal_country")
      format <- generator_fit_role_value(roles, i, "postal_format")
      postal_strategy <- generator_fit_role_value(roles, i, "postal_strategy", "generate")
      if (!identical(postal_strategy, "generate") || is.na(country) || is.na(format)) {
        add_blocker("postal_parameters_missing", "Postal generation needs approved country and format parameters; observed codes are not retained.", name)
      } else {
        columns[[i]] <- list(kind = "postal", country = country, format = format,
          missing_rate = generator_fit_missing_rate(x))
      }
      next
    }
    if (all(is.na(x))) {
      columns[[i]] <- generator_fit_all_missing(x)
      next
    }
    if (inherits(x, "Date")) {
      fitted <- generator_fit_date(x, "date", coarsen_dates)
      if (generator_fit_aggregate_collides(fitted, x)) {
        add_blocker("aggregate_source_collision", "A fitted aggregate exactly reproduces the complete source vector.", name)
      } else {
        columns[[i]] <- fitted
      }
      next
    }
    if (inherits(x, "POSIXct")) {
      timezone <- attr(x, "tzone") %||% "UTC"
      timezone <- if (length(timezone) == 0L || !nzchar(as.character(timezone[[1L]]))) {
        "UTC"
      } else {
        as.character(timezone[[1L]])
      }
      fitted <- generator_fit_date(x, "posixct", coarsen_dates, timezone = timezone,
        format = "%Y-%m-%d %H:%M:%S", has_time = TRUE)
      if (generator_fit_aggregate_collides(fitted, x)) {
        add_blocker("aggregate_source_collision", "A fitted aggregate exactly reproduces the complete source vector.", name)
      } else {
        columns[[i]] <- fitted
      }
      next
    }
    if (identical(role, "date") && is.character(x)) {
      date_info <- parse_date_like_character(x)
      parsed <- if (is.null(date_info)) NULL else date_info$parsed
      if (is.null(parsed) || any(is.na(parsed[!is.na(x)]))) {
        add_blocker("unvalidated_character_date", "Character date/time column has no fully validated format.", name)
      } else {
        fitted <- generator_fit_date(
          parsed,
          "character_date",
          coarsen_dates,
          format = date_info$format,
          has_date = date_info$has_date,
          has_time = date_info$has_time,
          period_mode = date_info$period_mode %||% "none",
          parser = date_info$parser %||% "strptime",
          month_style = date_info$month_style,
          period_tokens = dg_period_tokens(x[!is.na(x) & nzchar(trimws(x))])
        )
        if (generator_fit_aggregate_collides(fitted, parsed)) {
          add_blocker("aggregate_source_collision", "A fitted aggregate exactly reproduces the complete source vector.", name)
        } else {
          columns[[i]] <- fitted
        }
      }
      next
    }
    if (is.logical(x)) {
      columns[[i]] <- generator_fit_logical(x)
      next
    }
    if (is.numeric(x) && !is.factor(x)) {
      fitted <- generator_fit_numeric(x)
      if (is.null(fitted)) {
        add_blocker("non_finite_numeric", "Numeric columns must contain only finite observed values.", name)
      } else {
        observed <- x[!is.na(x)]
        if (!identical(fitted$distribution, "degenerate") &&
          length(observed) < generator_fit_minimum_numeric_support()) {
          add_blocker("insufficient_numeric_support", "Numeric summaries require at least five observed values.", name)
        }
        if (generator_fit_aggregate_collides(fitted, observed)) {
          add_blocker("aggregate_source_collision", "A fitted aggregate exactly reproduces the complete source vector.", name)
        }
        if (!any(vapply(blockers, function(blocker) identical(blocker$column, name), logical(1)))) {
          columns[[i]] <- fitted
        }
      }
      next
    }
    if (is.character(x) || is.factor(x)) {
      if (!label_strategy %in% c("preserve", "mask_rare")) {
        add_blocker("invalid_label_strategy", "Column has an unsupported label strategy.", name)
        next
      }
      fitted <- generator_fit_categorical(x, rare_level_min_n, label_strategy, merge_rare)
      counts <- if (is.null(fitted)) integer() else fitted$counts
      if (identical(label_strategy, "preserve") && !merge_rare && any(counts < rare_level_min_n)) {
        add_blocker("unsafe_rare_labels", "Rare categorical labels must be masked or merged before fitting.", name)
      } else {
        columns[[i]] <- fitted
      }
      next
    }
    add_blocker("unsupported_class", "Column class is not supported by the V1 internal compiler.", name)
  }

  report <- generator_fit_report(blockers, warnings)
  if (!report$eligible) {
    columns <- list()
  }
  exact_row_index <- if (report$eligible) {
    generator_fit_exact_row_index(data, exact_row_key)
  } else {
    NULL
  }
  result <- structure(
    list(
      schema_version = generator_schema_version(),
      engine = "internal",
      eligible = report$eligible,
      columns = columns,
      risk_report = report,
      roles = generator_fit_role_state(roles),
      settings = generator_fit_settings(spec),
      exact_row_index = exact_row_index
    ),
    class = "dataganger_generator"
  )
  validate_internal_generator(result)
  result
}
