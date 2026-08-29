generator_schema_version <- function() {
  1L
}

canonical_json <- function(x) {
  canonical <- canonicalize_generator_value(x)
  as.character(jsonlite::toJSON(
    canonical,
    auto_unbox = TRUE,
    digits = NA,
    null = "null",
    na = "null",
    pretty = FALSE
  ))
}

semantic_hash <- function(x) {
  digest::digest(
    canonical_json(x),
    algo = "sha256",
    serialize = FALSE
  )
}

canonicalize_generator_value <- function(x, path = "$") {
  if (is.null(x)) {
    return(NULL)
  }

  if (is.object(x)) {
    generator_unsafe_abort(sprintf(
      "Unsafe classed content at %s is not allowed in canonical JSON.",
      path
    ))
  }

  if (typeof(x) == "list") {
    extra_attributes <- setdiff(names(attributes(x)), "names")
    if (length(extra_attributes) > 0L) {
      generator_unsafe_abort(sprintf(
        "Unsafe attributed content at %s is not allowed in canonical JSON.",
        path
      ))
    }
    return(canonicalize_generator_list(x, path))
  }

  allowed <- is.logical(x) || is.integer(x) ||
    is.double(x) || is.character(x)
  if (!allowed || !is.atomic(x)) {
    generator_unsafe_abort(sprintf(
      "Unsafe content type %s at %s is not allowed in canonical JSON.",
      typeof(x),
      path
    ))
  }

  extra_attributes <- setdiff(names(attributes(x)), "names")
  if (length(extra_attributes) > 0L) {
    generator_unsafe_abort(sprintf(
      "Unsafe attributed content at %s is not allowed in canonical JSON.",
      path
    ))
  }
  if (anyNA(x) || (is.double(x) && any(!is.finite(x)))) {
    generator_unsafe_abort(sprintf(
      "Missing or non-finite values at %s are not allowed in canonical JSON.",
      path
    ))
  }

  value_names <- names(x)
  if (!is.null(value_names)) {
    return(canonicalize_generator_list(as.list(x), path))
  }

  if (is.character(x)) {
    x <- enc2utf8(x)
  }
  if (is.double(x)) {
    x[x == 0] <- 0
  }
  x
}

canonicalize_generator_list <- function(x, path) {
  value_names <- names(x)
  if (is.null(value_names)) {
    return(lapply(
      seq_along(x),
      function(index) {
        canonicalize_generator_value(
          x[[index]],
          sprintf("%s[%s]", path, index)
        )
      }
    ))
  }

  if (length(value_names) != length(x) ||
    anyNA(value_names) ||
    any(!nzchar(value_names)) ||
    anyDuplicated(value_names)) {
    generator_unsafe_abort(sprintf(
      "Object keys at %s must be non-empty and unique.",
      path
    ))
  }

  value_names <- enc2utf8(value_names)
  index <- order(value_names, method = "radix")
  x <- x[index]
  value_names <- value_names[index]
  result <- Map(
    function(value, name) {
      canonicalize_generator_value(value, sprintf("%s.%s", path, name))
    },
    x,
    value_names
  )
  stats::setNames(result, value_names)
}

validate_generator_named_object <- function(x, object) {
  if (!is.list(x) || length(x) == 0L || is.null(names(x))) {
    generator_schema_abort(sprintf("%s must be a non-empty named list.", object))
  }
  canonical_json(x)
  invisible(x)
}

generation_limits <- function(n = c(1L, .Machine$integer.max),
                              datasets = c(1L, 1L),
                              seed = c(0L, .Machine$integer.max)) {
  limits <- structure(
    list(
      seed = seed,
      n = n,
      datasets = datasets
    ),
    class = "dataganger_generation_limits"
  )
  validate_generation_limits(limits)
  limits$seed <- as.integer(limits$seed)
  limits$n <- as.integer(limits$n)
  limits$datasets <- as.integer(limits$datasets)
  limits
}

generator_contract <- function(policy,
                               allowed,
                               compatibility,
                               contract_version = "1.0.0",
                               schema_version = generator_schema_version()) {
  validate_generator_schema_version(schema_version, "Contract")
  validate_generator_semver(contract_version)
  validate_generator_named_object(policy, "Contract policy")
  validate_generation_limits(allowed)
  validate_generator_named_object(
    compatibility,
    "Contract compatibility"
  )
  policy <- canonicalize_generator_value(policy)
  compatibility <- canonicalize_generator_value(compatibility)

  contract <- list(
    schema_version = as.integer(schema_version),
    contract_version = contract_version,
    contract_id = NULL,
    policy = policy,
    allowed = structure(
      lapply(unclass(allowed), as.integer),
      class = "dataganger_generation_limits"
    ),
    compatibility = compatibility
  )
  contract$contract_id <- semantic_hash(contract_hash_payload(contract))
  class(contract) <- "dataganger_contract"
  validate_generator_contract(contract)
  contract
}

contract_hash_payload <- function(contract) {
  list(
    schema_version = contract$schema_version,
    contract_version = contract$contract_version,
    policy = contract$policy,
    allowed = unclass(contract$allowed),
    compatibility = contract$compatibility
  )
}

generation_request <- function(contract, request) {
  validate_generator_contract(contract)
  validate_generator_fields(
    request,
    expected = c("seed", "n", "datasets"),
    object = "Request overlay",
    abort = generator_request_abort
  )
  validate_generation_request_values(
    seed = request$seed,
    n = request$n,
    datasets = request$datasets,
    limits = contract$allowed
  )

  result <- list(
    schema_version = generator_schema_version(),
    request_id = NULL,
    contract_id = contract$contract_id,
    seed = as.integer(request$seed),
    n = as.integer(request$n),
    datasets = as.integer(request$datasets)
  )
  result$request_id <- semantic_hash(request_hash_payload(result))
  class(result) <- "dataganger_generation_request"
  validate_generation_request(result, contract)
  result
}

request_hash_payload <- function(request) {
  list(
    schema_version = request$schema_version,
    contract_id = request$contract_id,
    seed = request$seed,
    n = request$n,
    datasets = request$datasets
  )
}

#' @export
summary.dataganger_contract <- function(object, ...) {
  validate_generator_contract(object)
  structure(
    list(
      type = "dataganger_contract",
      schema_version = object$schema_version,
      contract_version = object$contract_version,
      contract_id = object$contract_id,
      allowed = unclass(object$allowed),
      policy_sections = names(object$policy),
      compatibility_fields = names(object$compatibility)
    ),
    class = "summary_dataganger_contract"
  )
}

#' @export
print.summary_dataganger_contract <- function(x, ...) {
  cat("DataGangeR generator contract\n")
  cat("  schema version: ", x$schema_version, "\n", sep = "")
  cat("  contract version: ", x$contract_version, "\n", sep = "")
  cat("  contract ID: ", x$contract_id, "\n", sep = "")
  cat("  policy sections: ", paste(x$policy_sections, collapse = ", "), "\n", sep = "")
  cat(
    "  allowed requests: seed [",
    x$allowed$seed[[1L]],
    ", ",
    x$allowed$seed[[2L]],
    "], n [",
    x$allowed$n[[1L]],
    ", ",
    x$allowed$n[[2L]],
    "], datasets [",
    x$allowed$datasets[[1L]],
    ", ",
    x$allowed$datasets[[2L]],
    "]\n",
    sep = ""
  )
  cat(
    "  compatibility fields: ",
    paste(x$compatibility_fields, collapse = ", "),
    "\n",
    sep = ""
  )
  invisible(x)
}

#' @export
print.dataganger_contract <- function(x, ...) {
  print(summary(x), ...)
  invisible(x)
}

#' @export
summary.dataganger_generation_request <- function(object, ...) {
  validate_generator_fields(
    unclass(object),
    expected = c("schema_version", "request_id", "contract_id", "seed", "n", "datasets"),
    object = "Generation request",
    abort = generator_request_abort
  )
  validate_generator_schema_version(object$schema_version, "Generation request")
  validate_generator_hash(object$request_id, "request_id")
  validate_generator_hash(object$contract_id, "contract_id")
  validate_generation_request_values(
    seed = object$seed,
    n = object$n,
    datasets = object$datasets,
    limits = generation_limits(
      seed = c(0L, .Machine$integer.max),
      n = c(1L, .Machine$integer.max),
      datasets = c(1L, .Machine$integer.max)
    )
  )
  expected_id <- semantic_hash(request_hash_payload(object))
  if (!identical(object$request_id, expected_id)) {
    generator_tamper_abort(
      "Generation request content does not match request_id. Refuse the tampered request."
    )
  }
  structure(
    list(
      type = "dataganger_generation_request",
      schema_version = object$schema_version,
      request_id = object$request_id,
      contract_id = object$contract_id,
      seed = object$seed,
      n = object$n,
      datasets = object$datasets
    ),
    class = "summary_dataganger_generation_request"
  )
}

#' @export
print.summary_dataganger_generation_request <- function(x, ...) {
  cat("DataGangeR generation request\n")
  cat("  schema version: ", x$schema_version, "\n", sep = "")
  cat("  request ID: ", x$request_id, "\n", sep = "")
  cat("  contract ID: ", x$contract_id, "\n", sep = "")
  cat("  seed: ", x$seed, "\n", sep = "")
  cat("  rows: ", x$n, "\n", sep = "")
  cat("  datasets: ", x$datasets, "\n", sep = "")
  invisible(x)
}

#' @export
print.dataganger_generation_request <- function(x, ...) {
  print(summary(x), ...)
  invisible(x)
}
