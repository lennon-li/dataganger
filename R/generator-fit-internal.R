generator_fit_issue <- function(code, message, column = NA_character_) {
  list(code = code, message = message, column = column)
}

generator_fit_csprng_key <- function(n = 32L) {
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 16L ||
    n != floor(n)) {
    return(NULL)
  }
  key <- tryCatch(
    openssl::rand_bytes(as.integer(n)),
    error = function(e) raw(0)
  )
  if (length(key) == n) {
    return(key)
  }
  handle <- tryCatch(file("/dev/urandom", open = "rb", raw = TRUE), error = function(e) NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(try(close(handle), silent = TRUE), add = TRUE)
  key <- tryCatch(readBin(handle, what = "raw", n = as.integer(n)),
    error = function(e) raw(0))
  if (length(key) != n) NULL else key
}

generator_fit_row_payload <- function(data, row) {
  values <- lapply(data, function(x) {
    value <- x[[row]]
    if (inherits(x, "Date") || inherits(x, "POSIXct")) {
      list(type = class(x)[[1L]], missing = is.na(value), value = if (is.na(value)) {
        NULL
      } else {
        as.numeric(value)
      })
    } else if (is.factor(x)) {
      list(type = "character", missing = is.na(value), value = if (is.na(value)) NULL else as.character(value))
    } else {
      list(type = typeof(x), missing = is.na(value), value = if (is.na(value)) NULL else value)
    }
  })
  names(values) <- names(data)
  values
}

generator_fit_row_fingerprint <- function(data, row, key) {
  payload <- serialize(generator_fit_row_payload(data, row), NULL, version = 3)
  digest::hmac(key, payload, algo = "sha256", serialize = FALSE)
}

generator_fit_exact_row_index <- function(data, key) {
  if (is.null(key) || !is.raw(key)) {
    return(NULL)
  }
  if (!nrow(data)) {
    return(list(
      key = key,
      fingerprints = character(),
      source_n = 0L,
      algorithm = "HMAC-SHA256"
    ))
  }
  fingerprints <- vapply(seq_len(nrow(data)), function(row) {
    generator_fit_row_fingerprint(data, row, key)
  }, character(1L))
  list(
    key = key,
    fingerprints = unique(fingerprints),
    source_n = as.integer(nrow(data)),
    algorithm = "HMAC-SHA256"
  )
}

generator_fit_role_state <- function(roles) {
  fields <- intersect(c(
    "variable", "recommended_role", "user_role", "simulation",
    "label_strategy", "postal_strategy", "postal_country", "postal_format",
    "identifies", "sensitive", "disclosure_role"
  ), names(roles))
  state <- lapply(roles[fields], function(x) {
    if (is.logical(x)) as.logical(x) else as.character(x)
  })
  names(state) <- fields
  state
}

generator_fit_settings <- function(spec) {
  rare_level_min_n <- spec$rare_level_min_n %||% 5L
  rare_level_min_n <- suppressWarnings(as.integer(rare_level_min_n))
  if (is.na(rare_level_min_n) || rare_level_min_n <= 1L) {
    rare_level_min_n <- 5L
  }
  list(
    purpose = as.character(spec$purpose %||% "development"),
    name_strategy = as.character(spec$name_strategy %||% "preserve"),
    k_anon = as.integer(spec$k_anon %||% 5L),
    rare_level_min_n = rare_level_min_n,
    preserve_missingness = as.character(spec$preserve_missingness %||% "approx"),
    coarsen_dates = isTRUE(spec$coarsen_dates %||% TRUE),
    merge_rare = isTRUE(spec$merge_rare %||% FALSE),
    free_text_strategy = as.character(spec$free_text_strategy %||% "categorical")
  )
}

generator_fit_empty_issues <- function() {
  list(code = character(), message = character(), column = character())
}

generator_fit_issue_table <- function(issues) {
  if (length(issues) == 0L) {
    return(generator_fit_empty_issues())
  }
  list(
    code = vapply(issues, `[[`, character(1), "code"),
    message = vapply(issues, `[[`, character(1), "message"),
    column = vapply(issues, `[[`, character(1), "column")
  )
}

generator_fit_report <- function(blockers = list(), warnings = list()) {
  structure(
    list(
      schema_version = generator_schema_version(),
      eligible = length(blockers) == 0L,
      blockers = generator_fit_issue_table(blockers),
      warnings = generator_fit_issue_table(warnings)
    ),
    class = "dataganger_generator_risk_report"
  )
}

generator_fit_missing_rate <- function(x) {
  if (length(x) == 0L) {
    return(0)
  }
  sum(is.na(x)) / length(x)
}

generator_fit_precision <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L || all(x == floor(x))) {
    return(0L)
  }
  values <- format(x, scientific = FALSE, trim = TRUE, digits = 15)
  decimals <- sub("^[^.]*\\.?", "", values)
  as.integer(min(10L, max(nchar(decimals))))
}

generator_fit_numeric <- function(x) {
  observed <- x[!is.na(x)]
  if (length(observed) == 0L) {
    return(NULL)
  }
  if (any(!is.finite(observed))) {
    return(NULL)
  }

  storage <- if (is.integer(x)) "integer" else "double"
  lower <- min(observed)
  upper <- max(observed)
  common <- list(
    kind = "numeric",
    storage = storage,
    bounds = list(lower = as.numeric(lower), upper = as.numeric(upper)),
    precision = generator_fit_precision(observed),
    missing_rate = generator_fit_missing_rate(x),
    observed_n = as.integer(length(observed))
  )
  if (identical(lower, upper)) {
    return(c(common, list(distribution = "degenerate", value = as.numeric(lower))))
  }

  bins <- min(16L, max(2L, as.integer(floor(sqrt(length(observed))))))
  histogram <- graphics::hist(observed, breaks = bins, plot = FALSE)
  c(common, list(
    distribution = "histogram",
    breaks = as.numeric(histogram$breaks),
    counts = as.integer(histogram$counts)
  ))
}

generator_fit_minimum_numeric_support <- function() {
  5L
}

generator_fit_aggregate_collides <- function(summary, source) {
  source <- as.numeric(source[!is.na(source)])
  if (is.list(summary) && is.list(summary$bounds) &&
    all(c("lower", "upper") %in% names(summary$bounds)) &&
    length(source) == 2L) {
    bounds <- as.numeric(c(summary$bounds$lower, summary$bounds$upper))
    if (length(bounds) == 2L && all(is.finite(bounds)) &&
      identical(sort(bounds, method = "radix"), sort(source, method = "radix"))) {
      return(TRUE)
    }
  }
  walk <- function(value) {
    if (is.atomic(value) && length(value) == length(source) && length(source) > 1L &&
      is.numeric(value)) {
      candidate <- as.numeric(value)
      if (identical(candidate, source) ||
        identical(sort(candidate, method = "radix"), sort(source, method = "radix"))) {
        return(TRUE)
      }
    }
    if (is.list(value)) {
      return(any(vapply(value, walk, logical(1))))
    }
    FALSE
  }
  walk(summary)
}

generator_fit_categorical <- function(x, rare_level_min_n, label_strategy,
                                       merge_rare) {
  observed <- as.character(x[!is.na(x)])
  if (length(observed) == 0L) {
    return(NULL)
  }
  levels <- sort(unique(observed), method = "radix")
  counts <- as.integer(table(observed)[levels])
  rare <- counts < rare_level_min_n
  protection <- "none"

  if (any(rare) && identical(label_strategy, "mask_rare")) {
    masked <- mask_rare_category_labels(
      observed,
      levels,
      levels,
      counts,
      rare_level_min_n
    )
    observed <- masked$x_obs
    levels <- sort(unique(observed), method = "radix")
    counts <- as.integer(table(observed)[levels])
    protection <- "mask_rare"
  } else if (any(rare) && isTRUE(merge_rare)) {
    observed[observed %in% levels[rare]] <- ".other"
    levels <- sort(unique(observed), method = "radix")
    counts <- as.integer(table(observed)[levels])
    protection <- "merge_rare"
  }

  list(
    kind = "categorical",
    levels = as.character(levels),
    counts = as.integer(counts),
    probabilities = as.numeric(counts / sum(counts)),
    rare_label_protection = protection,
    missing_rate = generator_fit_missing_rate(x),
    observed_n = as.integer(length(observed))
  )
}

generator_fit_logical <- function(x) {
  observed <- x[!is.na(x)]
  if (length(observed) == 0L) {
    return(NULL)
  }
  list(
    kind = "logical",
    true_probability = as.numeric(mean(observed)),
    false_probability = as.numeric(1 - mean(observed)),
    missing_rate = generator_fit_missing_rate(x),
    observed_n = as.integer(length(observed))
  )
}

generator_fit_date <- function(x, kind, coarsen_dates, timezone = "UTC",
                               format = "%Y-%m-%d", has_date = TRUE,
                               has_time = FALSE, period_mode = "none",
                               parser = "strptime", month_style = NULL,
                               period_tokens = NULL) {
  observed <- x[!is.na(x)]
  if (length(observed) == 0L) {
    return(NULL)
  }
  values <- as.numeric(observed)
  if (any(!is.finite(values))) {
    return(NULL)
  }
  list(
    kind = kind,
    bounds = list(lower = min(values), upper = max(values)),
    granularity = if (isTRUE(coarsen_dates)) "coarsened" else if (has_time) "second" else "day",
    format = format,
    timezone = timezone,
    has_date = isTRUE(has_date),
    has_time = isTRUE(has_time),
    period_mode = period_mode,
    parser = parser,
    month_style = month_style,
    period_tokens = period_tokens,
    missing_rate = generator_fit_missing_rate(x),
    observed_n = as.integer(length(observed))
  )
}

generator_fit_all_missing <- function(x) {
  storage <- if (inherits(x, "Date")) {
    "Date"
  } else if (inherits(x, "POSIXct")) {
    "POSIXct"
  } else if (is.logical(x)) {
    "logical"
  } else if (is.integer(x)) {
    "integer"
  } else if (is.numeric(x)) {
    "double"
  } else {
    "character"
  }
  list(kind = "all_missing", storage = storage, missing_rate = 1, observed_n = 0L)
}

generator_fit_role_value <- function(roles, row, field, default = NA_character_) {
  if (!field %in% names(roles)) {
    return(default)
  }
  value <- roles[[field]][[row]]
  if (length(value) != 1L || is.na(value) || !nzchar(as.character(value))) {
    return(default)
  }
  as.character(value)
}

generator_fit_effective_role <- function(roles, row) {
  user <- generator_fit_role_value(roles, row, "user_role")
  if (!is.na(user)) {
    return(user)
  }
  generator_fit_role_value(roles, row, "recommended_role", "unknown")
}

generator_fit_recognized_roles <- function() {
  c(
    "unknown", "numeric", "categorical candidate", "categorical", "date",
    "postal code", "postal_code", "free text", "free_text", "alphanumeric ID",
    "alphanumeric_id", "label_check", "logical"
  )
}

generator_fit_required_role_fields <- function() {
  c(
    "variable", "recommended_role", "user_role", "simulation", "label_strategy",
    "postal_strategy", "postal_country"
  )
}

generator_fit_validate_roles <- function(roles, data) {
  required <- generator_fit_required_role_fields()
  valid <- inherits(roles, "dataganger_roles") && is.data.frame(roles) &&
    all(required %in% names(roles)) &&
    is.character(roles$variable) && !anyNA(roles$variable) &&
    !anyDuplicated(roles$variable) && identical(roles$variable, names(data)) &&
    is.character(roles$recommended_role) && !anyNA(roles$recommended_role) &&
    all(roles$recommended_role %in% generator_fit_recognized_roles()) &&
    is.character(roles$user_role) &&
    all(is.na(roles$user_role) | roles$user_role %in% generator_fit_recognized_roles()) &&
    is.character(roles$simulation) && !anyNA(roles$simulation) &&
    all(roles$simulation %in% c("synthesize", "drop", "pass_through", "scramble")) &&
    is.character(roles$label_strategy) &&
    all(is.na(roles$label_strategy) | roles$label_strategy %in% c("preserve", "mask_rare")) &&
    is.character(roles$postal_strategy) &&
    all(is.na(roles$postal_strategy) | roles$postal_strategy %in% c("generate", "resample")) &&
    is.character(roles$postal_country)
  isTRUE(valid)
}

generator_fit_supported_column <- function(x) {
  if (isS4(x) || is.pairlist(x) || is.list(x) || is.matrix(x) || is.array(x) ||
    is.function(x) || is.environment(x) || is.call(x) || is.language(x) ||
    typeof(x) == "externalptr" || inherits(x, "formula")) {
    return(FALSE)
  }
  if (inherits(x, "Date")) {
    return(identical(class(x), "Date"))
  }
  if (inherits(x, "POSIXct")) {
    return(identical(class(x), c("POSIXct", "POSIXt")))
  }
  if (is.factor(x)) {
    return(identical(class(x), "factor") || identical(class(x), c("ordered", "factor")))
  }
  is.atomic(x) && is.null(attr(x, "class", exact = TRUE)) &&
    (is.logical(x) || is.integer(x) || is.double(x) || is.character(x))
}

generator_fit_raw_contains <- function(haystack, needle) {
  if (length(needle) == 0L || length(needle) > length(haystack)) {
    return(FALSE)
  }
  last <- length(haystack) - length(needle) + 1L
  any(vapply(seq_len(last), function(i) {
    identical(haystack[i:(i + length(needle) - 1L)], needle)
  }, logical(1)))
}

# A clean canary audit is evidence only. It cannot prove that fitted state has
# no leakage, because it can inspect only known canaries and unsafe structures.
generator_fitted_state_audit <- function(state, canaries = list()) {
  findings <- list(
    source_data_frames = character(),
    source_vectors = character(),
    unsafe_state = character(),
    unsafe_attributes = character(),
    serialized_canaries = character()
  )
  allowed_attributes <- function(value, path) {
    attributes <- attributes(value)
    if (is.null(attributes)) {
      return(character())
    }
    allowed <- "names"
    if (identical(path, "$") && inherits(value, "dataganger_generator")) {
      allowed <- c(allowed, "class")
    }
    if (inherits(value, "dataganger_generator_risk_report")) {
      allowed <- c(allowed, "class")
    }
    setdiff(names(attributes), allowed)
  }
  walk <- function(value, path) {
    if (is.null(value)) {
      return(invisible(NULL))
    }
    if (is.environment(value) || is.function(value) || is.call(value) ||
      is.language(value) || is.pairlist(value) || typeof(value) == "externalptr" ||
      inherits(value, "formula")) {
      findings$unsafe_state <<- c(findings$unsafe_state, path)
      return(invisible(NULL))
    }
    if (isS4(value)) {
      findings$unsafe_state <<- c(findings$unsafe_state, path)
      for (slot_name in methods::slotNames(value)) {
        walk(methods::slot(value, slot_name), sprintf("%s@%s", path, slot_name))
      }
      return(invisible(NULL))
    }
    if (is.data.frame(value)) {
      findings$source_data_frames <<- c(findings$source_data_frames, path)
    }
    for (name in names(canaries)) {
      if (identical(value, canaries[[name]])) {
        findings$source_vectors <<- c(findings$source_vectors, name)
      }
    }
    value_attributes <- attributes(value)
    unexpected <- allowed_attributes(value, path)
    if (length(unexpected) > 0L) {
      findings$unsafe_attributes <<- c(
        findings$unsafe_attributes,
        sprintf("%s@%s", path, unexpected)
      )
    }
    if (!is.null(value_attributes)) {
      for (attribute_name in names(value_attributes)) {
        walk(value_attributes[[attribute_name]], sprintf("%s@%s", path, attribute_name))
      }
    }
    if (is.list(value)) {
      item_names <- names(value)
      for (i in seq_along(value)) {
        item <- if (is.null(item_names) || !nzchar(item_names[[i]])) {
          sprintf("%s[[%s]]", path, i)
        } else {
          sprintf("%s$%s", path, item_names[[i]])
        }
        walk(value[[i]], item)
      }
    }
    invisible(NULL)
  }
  walk(state, "$")

  serialized <- serialize(state, NULL, version = 3)
  for (name in names(canaries)) {
    canary <- canaries[[name]]
    if (is.character(canary) && !anyNA(canary)) {
      patterns <- lapply(enc2utf8(canary[nzchar(canary)]), charToRaw)
      if (any(vapply(patterns, function(pattern) {
        generator_fit_raw_contains(serialized, pattern)
      }, logical(1)))) {
        findings$serialized_canaries <- c(findings$serialized_canaries, name)
      }
    }
  }
  findings <- lapply(findings, unique)
  structure(
    list(clean = all(lengths(findings) == 0L), findings = findings),
    class = "dataganger_generator_fitted_state_audit"
  )
}

validate_generator_issue_table <- function(x, object) {
  validate_generator_fields(
    x,
    expected = c("code", "message", "column"),
    object = object
  )
  valid <- all(vapply(x, is.character, logical(1))) &&
    length(x$code) == length(x$message) && length(x$code) == length(x$column) &&
    !anyNA(x$code) && !any(!nzchar(x$code)) && !anyNA(x$message) && !any(!nzchar(x$message))
  if (!isTRUE(valid)) {
    generator_schema_abort(sprintf("%s must contain equally sized character fields.", object))
  }
  invisible(x)
}

validate_generator_risk_report <- function(report) {
  if (!identical(attr(report, "class", exact = TRUE), "dataganger_generator_risk_report") ||
    !is.list(report)) {
    generator_schema_abort("Fitted generator risk report has an invalid class.")
  }
  validate_generator_fields(
    unclass(report),
    expected = c("schema_version", "eligible", "blockers", "warnings"),
    object = "Fitted generator risk report"
  )
  validate_generator_schema_version(report$schema_version, "Fitted generator risk report")
  if (!is.logical(report$eligible) || length(report$eligible) != 1L || is.na(report$eligible)) {
    generator_schema_abort("Fitted generator risk report eligible must be one logical value.")
  }
  validate_generator_issue_table(report$blockers, "Fitted generator risk report blockers")
  validate_generator_issue_table(report$warnings, "Fitted generator risk report warnings")
  if (!identical(report$eligible, length(report$blockers$code) == 0L)) {
    generator_schema_abort("Fitted generator risk report eligibility contradicts its blockers.")
  }
  invisible(report)
}

validate_internal_generator <- function(generator) {
  if (!identical(attr(generator, "class", exact = TRUE), "dataganger_generator") ||
    !is.list(generator)) {
    generator_schema_abort("Fitted generator must be a dataganger_generator list.")
  }
  validate_generator_fields(
    unclass(generator),
    expected = c(
      "schema_version", "engine", "eligible", "columns", "risk_report",
      "roles", "settings", "exact_row_index"
    ),
    object = "Fitted generator"
  )
  validate_generator_schema_version(generator$schema_version, "Fitted generator")
  if (!identical(generator$engine, "internal") || !is.logical(generator$eligible) ||
    length(generator$eligible) != 1L || is.na(generator$eligible) || !is.list(generator$columns) ||
    !inherits(generator$risk_report, "dataganger_generator_risk_report")) {
    generator_schema_abort("Fitted generator has an invalid internal schema.")
  }
  validate_generator_risk_report(generator$risk_report)
  if (!identical(generator$eligible, generator$risk_report$eligible)) {
    generator_schema_abort("Fitted generator eligibility contradicts its risk report.")
  }
  if (generator$eligible) {
    if (!is.list(generator$roles) || is.null(names(generator$roles)) ||
      !is.list(generator$settings) || is.null(names(generator$settings)) ||
      !is.list(generator$exact_row_index)) {
      generator_schema_abort("Eligible fitted generator is missing private runtime state.")
    }
    index <- generator$exact_row_index
    validate_generator_fields(
      index,
      expected = c("key", "fingerprints", "source_n", "algorithm"),
      object = "Fitted generator exact-row index"
    )
    if (!is.raw(index$key) || length(index$key) < 16L ||
      !is.character(index$fingerprints) || anyNA(index$fingerprints) ||
      any(!grepl("^[0-9a-f]{64}$", index$fingerprints)) ||
      !generator_is_integerish(index$source_n) || length(index$source_n) != 1L ||
      !identical(index$algorithm, "HMAC-SHA256")) {
      generator_schema_abort("Fitted generator exact-row index has an invalid schema.")
    }
  } else if (!is.null(generator$exact_row_index)) {
    generator_schema_abort("Blocked fitted generators cannot retain exact-row state.")
  }
  column_names <- names(generator$columns)
  if (generator$eligible && length(generator$columns) > 0L &&
    (is.null(column_names) || anyNA(column_names) || any(!nzchar(column_names)) ||
      anyDuplicated(column_names))) {
    generator_schema_abort("Eligible fitted generator columns must be uniquely named.")
  }
  if (!generator$eligible && length(generator$columns) != 0L) {
    generator_schema_abort("Blocked fitted generators cannot retain fitted columns.")
  }
  audit <- generator_fitted_state_audit(generator)
  if (!isTRUE(audit$clean)) {
    generator_unsafe_abort("Fitted generator contains unsafe retained state.")
  }
  invisible(generator)
}
