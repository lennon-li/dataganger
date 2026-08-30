# Trusted runtime for the dependency-free fitted internal generator.

generator_runtime_hashable <- function(value) {
  if (is.list(value)) {
    return(lapply(value, generator_runtime_hashable))
  }
  if (is.atomic(value) && anyNA(value)) {
    value <- as.character(value)
    value[is.na(value)] <- "<missing>"
  }
  value
}

generator_runtime_revision_id <- function(generator) {
  semantic_hash(list(
    schema_version = generator$schema_version,
    engine = generator$engine,
    columns = generator_runtime_hashable(generator$columns),
    roles = generator_runtime_hashable(generator$roles),
    settings = generator_runtime_hashable(generator$settings)
  ))
}

generator_runtime_seed <- function(generator, seed, index) {
  digest <- semantic_hash(list(
    generator = generator_runtime_revision_id(generator),
    seed = as.integer(seed),
    dataset = as.integer(index)
  ))
  as.integer(strtoi(substr(digest, 1L, 7L), base = 16L))
}

generator_runtime_missing <- function(value, rate, n) {
  if (!length(value) || !is.finite(rate) || rate <= 0) {
    return(value)
  }
  value[stats::runif(n) < min(1, rate)] <- NA
  value
}

generator_runtime_numeric <- function(state, n) {
  if (identical(state$distribution, "degenerate")) {
    out <- rep(state$value, n)
  } else {
    counts <- as.numeric(state$counts)
    probabilities <- counts / sum(counts)
    bins <- sample(seq_along(counts), n, replace = TRUE, prob = probabilities)
    lower <- state$breaks[bins]
    upper <- state$breaks[bins + 1L]
    out <- lower + stats::runif(n) * (upper - lower)
    out[out == upper & bins < length(counts)] <- lower[out == upper & bins < length(counts)]
  }
  out <- pmax(state$bounds$lower, pmin(state$bounds$upper, out))
  if (identical(state$storage, "integer")) {
    return(as.integer(round(out)))
  }
  round(out, digits = as.integer(state$precision %||% 0L))
}

generator_runtime_categorical <- function(state, n) {
  sample(state$levels, n, replace = TRUE, prob = state$probabilities)
}

generator_runtime_date_values <- function(state, n) {
  lower <- state$bounds$lower
  upper <- state$bounds$upper
  if (identical(lower, upper)) {
    return(rep(lower, n))
  }
  lower + stats::runif(n, min = 0, max = upper - lower)
}

generator_runtime_date <- function(state, n) {
  values <- generator_runtime_date_values(state, n)
  if (identical(state$kind, "date")) {
    out <- as.Date(values, origin = "1970-01-01")
    if (identical(state$granularity, "coarsened")) {
      out <- as.Date(format(out, "%Y-%m-01"))
    }
    return(out)
  }

  timezone <- state$timezone %||% "UTC"
  if (identical(state$kind, "posixct")) {
    out <- as.POSIXct(values, origin = "1970-01-01", tz = timezone)
    if (identical(state$granularity, "coarsened")) {
      out <- as.POSIXct(format(out, "%Y-%m-%d", tz = timezone), tz = timezone)
    }
    return(out)
  }

  candidate <- list(
    format = state$format,
    fmt = state$format,
    parser = state$parser %||% "strptime",
    period_mode = if (grepl("%p", state$format, fixed = TRUE)) "ascii" else "none",
    month_style = state$month_style
  )
  if (isTRUE(state$has_date) && !isTRUE(state$has_time)) {
    out <- as.Date(
      as.POSIXct(values, origin = "1970-01-01", tz = timezone),
      tz = timezone
    )
    if (identical(state$granularity, "coarsened")) {
      out <- as.Date(format(out, "%Y-%m-01"))
    }
    out <- as.POSIXct(out, tz = "UTC")
  } else if (isTRUE(state$has_time) && !isTRUE(state$has_date)) {
    out <- as.POSIXct(values, origin = "1970-01-01", tz = "UTC")
  } else {
    out <- as.POSIXct(values, origin = "1970-01-01", tz = "UTC")
    if (identical(state$granularity, "coarsened")) {
      out <- as.POSIXct(format(out, "%Y-%m-%d", tz = "UTC"), tz = "UTC")
    }
  }
  dg_format_date_candidate(
    out, candidate, tz = "UTC",
    tokens = state$period_tokens %||% list(am = "AM", pm = "PM")
  )
}

generator_runtime_postal <- function(state, n) {
  registry <- dg_postal_format_registry()
  country <- toupper(state$country %||% "")
  postal <- registry[[country]]
  if (is.null(postal) || !identical(postal$template, state$format)) {
    generator_schema_abort("Fitted postal generator has no approved registry format.")
  }
  out <- vapply(seq_len(n), function(i) {
    paste0(vapply(postal$slots, function(slot) {
      if (slot$type == "literal") slot$chars else sample(strsplit(slot$chars, "")[[1L]], 1L)
    }, character(1L)), collapse = "")
  }, character(1L))
  generator_runtime_missing(out, state$missing_rate, n)
}

generator_runtime_column <- function(state, n) {
  result <- switch(state$kind,
    numeric = generator_runtime_numeric(state, n),
    categorical = generator_runtime_categorical(state, n),
    logical = stats::runif(n) < state$true_probability,
    date = generator_runtime_date(state, n),
    posixct = generator_runtime_date(state, n),
    character_date = generator_runtime_date(state, n),
    postal = generator_runtime_postal(state, n),
    all_missing = switch(state$storage,
      Date = rep(as.Date(NA), n),
      POSIXct = rep(as.POSIXct(NA, tz = "UTC"), n),
      logical = rep(NA, n),
      integer = rep(NA_integer_, n),
      double = rep(NA_real_, n),
      rep(NA_character_, n)
    ),
    dropped = NULL,
    redacted = rep("[REDACTED]", n),
    generator_schema_abort(sprintf("Unsupported fitted column kind: %s.", state$kind))
  )
  if (identical(state$kind, "logical") || identical(state$kind, "character_date")) {
    result <- generator_runtime_missing(result, state$missing_rate, n)
  } else if (!identical(state$kind, "all_missing") &&
    !identical(state$kind, "postal") && !identical(state$kind, "character_date")) {
    result <- generator_runtime_missing(result, state$missing_rate, n)
  }
  result
}

generator_runtime_apply_names <- function(synthetic, settings) {
  strategy <- settings$name_strategy %||% "preserve"
  if (strategy %in% c("generic", "dictionary_only")) {
    names(synthetic) <- paste0("col_", seq_len(ncol(synthetic)))
  }
  synthetic
}

generator_runtime_one <- function(generator, n, seed) {
  roles <- generator_runtime_roles(generator)
  settings <- generator$settings
  synthetic <- withr::with_seed(seed, {
    columns <- list()
    for (name in names(generator$columns)) {
      value <- generator_runtime_column(generator$columns[[name]], n)
      if (!is.null(value)) columns[[name]] <- value
    }
    if (length(columns)) tibble::as_tibble(columns) else tibble::tibble(.rows = n)
  })

  # The fitted runtime has no source frame for level restoration or precision
  # matching. Those inputs were compiled into each column state at fit time.
  warnings <- character()
  synthetic <- withCallingHandlers(
    enforce_kanon(synthetic, roles = roles, k = settings$k_anon %||% 5L),
    warning = function(condition) {
      warnings <<- c(warnings, conditionMessage(condition))
      invokeRestart("muffleWarning")
    }
  )
  privacy <- generator_runtime_privacy_check(synthetic, generator, roles)
  diagnostics <- generator_runtime_summary_diagnostics(synthetic, generator)
  synthetic <- generator_runtime_apply_names(synthetic, settings)
  class(synthetic) <- c("dataganger_synthetic", class(synthetic))
  attr(synthetic, "engine") <- "internal_fitted"
  attr(synthetic, "generator_revision") <- generator_runtime_revision_id(generator)
  list(
    data = synthetic,
    warnings = warnings,
    privacy = privacy,
    diagnostics = diagnostics
  )
}

generator_runtime_request <- function(generator, contract, request, seed, n, datasets) {
  if (!is.null(request)) {
    if (is.null(contract)) {
      generator_request_abort("A generation request requires its contract.")
    }
    validate_generation_request(request, contract)
    return(request)
  }
  if (is.null(seed)) seed <- 0L
  if (is.null(n)) n <- 1L
  if (!generator_is_integerish(seed) || length(seed) != 1L || seed < 0L ||
    !generator_is_integerish(n) || length(n) != 1L || n < 1L ||
    !generator_is_integerish(datasets) || length(datasets) != 1L || datasets < 1L) {
    generator_request_abort("seed, n, and datasets must be positive scalar integers.")
  }
  if (!is.null(contract)) {
    return(generation_request(contract, list(
      seed = as.integer(seed), n = as.integer(n), datasets = as.integer(datasets)
    )))
  }
  list(
    request_id = semantic_hash(list(
      generator = generator_runtime_revision_id(generator), seed = as.integer(seed),
      n = as.integer(n), datasets = as.integer(datasets)
    )),
    contract_id = NULL,
    seed = as.integer(seed), n = as.integer(n), datasets = as.integer(datasets)
  )
}

generator_generate <- function(generator, request = NULL, contract = NULL,
                                seed = NULL, n = NULL, datasets = 1L) {
  validate_internal_generator(generator)
  if (!isTRUE(generator$eligible)) {
    generator_request_abort("Cannot generate from an ineligible fitted generator.")
  }
  request <- generator_runtime_request(generator, contract, request, seed, n, datasets)
  seeds <- vapply(seq_len(request$datasets), function(index) {
    generator_runtime_seed(generator, request$seed, index)
  }, integer(1L))
  runs <- lapply(seq_along(seeds), function(index) {
    generator_runtime_one(generator, request$n, seeds[[index]])
  })
  privacy <- lapply(runs, `[[`, "privacy")
  usable <- all(vapply(privacy, function(item) isTRUE(item$ok), logical(1L)))
  warnings <- unique(unlist(lapply(runs, `[[`, "warnings"), use.names = FALSE))
  result <- list(
    schema_version = generator_schema_version(),
    request_id = request$request_id,
    contract_id = request$contract_id,
    generator_revision = generator_runtime_revision_id(generator),
    seeds = seeds,
    outputs = if (usable) lapply(runs, `[[`, "data") else list(),
    privacy = privacy,
    diagnostics = lapply(runs, `[[`, "diagnostics"),
    warnings = warnings,
    usable = usable,
    blockers = lapply(privacy, `[[`, "blockers")
  )
  class(result) <- "dataganger_generation"
  result
}

generate_internal_generator <- generator_generate
