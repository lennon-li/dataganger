generator_abort <- function(message, class, call = parent.frame()) {
  cli::cli_abort(
    message,
    class = c(
      class,
      "dataganger_generator_validation_error",
      "dataganger_generator_error"
    ),
    call = call
  )
}

generator_schema_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_schema_error",
    call = call
  )
}

generator_request_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_request_error",
    call = call
  )
}

generator_unsafe_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_unsafe_content_error",
    call = call
  )
}

generator_tamper_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_tamper_error",
    call = call
  )
}

generator_is_integerish <- function(x) {
  is.numeric(x) &&
    length(x) > 0L &&
    !anyNA(x) &&
    all(is.finite(x)) &&
    all(x == floor(x)) &&
    all(x <= .Machine$integer.max)
}

validate_generator_fields <- function(x,
                                      expected,
                                      object,
                                      abort = generator_schema_abort) {
  if (!is.list(x) || is.null(names(x))) {
    abort(sprintf("%s must be a named list.", object))
  }

  actual <- names(x)
  if (anyNA(actual) || any(!nzchar(actual)) || anyDuplicated(actual)) {
    abort(sprintf("%s field names must be non-empty and unique.", object))
  }

  missing <- setdiff(expected, actual)
  if (length(missing) > 0L) {
    abort(sprintf(
      "Missing field%s in %s: %s.",
      if (length(missing) == 1L) "" else "s",
      object,
      paste(missing, collapse = ", ")
    ))
  }

  unknown <- setdiff(actual, expected)
  if (length(unknown) > 0L) {
    abort(sprintf(
      "Unknown field%s in %s: %s.",
      if (length(unknown) == 1L) "" else "s",
      object,
      paste(unknown, collapse = ", ")
    ))
  }

  invisible(x)
}

validate_generator_schema_version <- function(version, object) {
  if (!generator_is_integerish(version) || length(version) != 1L) {
    generator_schema_abort(sprintf(
      "%s schema_version must be one integer.",
      object
    ))
  }

  if (!identical(as.integer(version), generator_schema_version())) {
    generator_schema_abort(sprintf(
      paste0(
        "Unsupported %s schema version %s. ",
        "This DataGangeR build supports schema version %s."
      ),
      object,
      format(version),
      generator_schema_version()
    ))
  }

  invisible(version)
}

validate_generator_semver <- function(version, field = "contract_version") {
  valid <- is.character(version) &&
    length(version) == 1L &&
    !is.na(version) &&
    grepl(
      "^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$",
      version
    )

  if (!valid) {
    generator_schema_abort(sprintf(
      "%s must be a semantic version such as 1.0.0.",
      field
    ))
  }

  invisible(version)
}

validate_generator_hash <- function(value, field) {
  valid <- is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    grepl("^[0-9a-f]{64}$", value)

  if (!valid) {
    generator_schema_abort(sprintf(
      "%s must be a lowercase SHA-256 digest.",
      field
    ))
  }

  invisible(value)
}

validate_generation_limits <- function(limits) {
  validate_generator_fields(
    unclass(limits),
    expected = c("seed", "n", "datasets"),
    object = "Generation limits"
  )

  for (field in c("seed", "n", "datasets")) {
    value <- limits[[field]]
    if (!generator_is_integerish(value) || length(value) != 2L) {
      generator_abort(
        sprintf("Generation limit %s must be two finite integers.", field),
        class = "dataganger_generator_limits_error"
      )
    }
    if (value[[1L]] > value[[2L]]) {
      generator_abort(
        sprintf("Generation limit %s must be ordered from minimum to maximum.", field),
        class = "dataganger_generator_limits_error"
      )
    }
  }

  if (limits$seed[[1L]] < 0L) {
    generator_abort(
      "Generation seed limits cannot include negative values.",
      class = "dataganger_generator_limits_error"
    )
  }
  if (limits$n[[1L]] < 1L || limits$datasets[[1L]] < 1L) {
    generator_abort(
      "Generation n and datasets limits must be positive.",
      class = "dataganger_generator_limits_error"
    )
  }

  invisible(limits)
}

validate_generator_contract <- function(contract) {
  contract_class <- attr(contract, "class", exact = TRUE)
  if (!is.null(contract_class) &&
    !identical(contract_class, "dataganger_contract")) {
    generator_schema_abort(
      "Contract must be an unclassed list or a dataganger_contract object."
    )
  }

  expected <- c(
    "schema_version",
    "contract_version",
    "contract_id",
    "policy",
    "allowed",
    "compatibility"
  )
  validate_generator_fields(
    unclass(contract),
    expected = expected,
    object = "Contract"
  )
  validate_generator_schema_version(contract$schema_version, "Contract")
  validate_generator_semver(contract$contract_version)
  validate_generator_hash(contract$contract_id, "contract_id")

  validate_generator_named_object(contract$policy, "Contract policy")
  validate_generation_limits(contract$allowed)
  validate_generator_named_object(
    contract$compatibility,
    "Contract compatibility"
  )

  expected_id <- semantic_hash(contract_hash_payload(contract))
  if (!identical(contract$contract_id, expected_id)) {
    generator_tamper_abort(
      "Contract content does not match contract_id. Refuse the tampered contract."
    )
  }

  invisible(contract)
}

validate_generation_request_values <- function(seed, n, datasets, limits) {
  if (!generator_is_integerish(datasets) || length(datasets) != 1L) {
    generator_request_abort("Request datasets must be one integer.")
  }
  if (!generator_is_integerish(n) || length(n) != 1L) {
    generator_request_abort("Request n must be one integer.")
  }
  if (!generator_is_integerish(seed) || length(seed) != 1L) {
    generator_request_abort("Request seed must be one finite integer.")
  }

  datasets <- as.integer(datasets)
  generator_validate_bound(n, limits$n, "n")
  generator_validate_bound(datasets, limits$datasets, "datasets")
  generator_validate_bound(seed, limits$seed, "seed")
  invisible(NULL)
}

generator_validate_bound <- function(value, bounds, field) {
  if (any(value < bounds[[1L]] | value > bounds[[2L]])) {
    generator_request_abort(sprintf(
      "Request %s is outside the approved range [%s, %s].",
      field,
      bounds[[1L]],
      bounds[[2L]]
    ))
  }
  invisible(value)
}

validate_generation_request <- function(request, contract) {
  validate_generator_contract(contract)
  request_class <- attr(request, "class", exact = TRUE)
  if (!is.null(request_class) &&
    !identical(request_class, "dataganger_generation_request")) {
    generator_request_abort(
      "Request must be an unclassed list or a dataganger_generation_request object."
    )
  }

  expected <- c(
    "schema_version",
    "request_id",
    "contract_id",
    "seed",
    "n",
    "datasets"
  )
  validate_generator_fields(
    unclass(request),
    expected = expected,
    object = "Generation request",
    abort = generator_request_abort
  )
  validate_generator_schema_version(request$schema_version, "Generation request")
  validate_generator_hash(request$request_id, "request_id")
  validate_generator_hash(request$contract_id, "contract_id")

  if (!identical(request$contract_id, contract$contract_id)) {
    generator_request_abort(
      "Generation request targets a different contract_id."
    )
  }

  validate_generation_request_values(
    seed = request$seed,
    n = request$n,
    datasets = request$datasets,
    limits = contract$allowed
  )

  expected_id <- semantic_hash(request_hash_payload(request))
  if (!identical(request$request_id, expected_id)) {
    generator_tamper_abort(
      "Generation request content does not match request_id. Refuse the tampered request."
    )
  }

  invisible(request)
}
