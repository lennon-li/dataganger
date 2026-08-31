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

# ---------------------------------------------------------------------------
# Canonical data hash
#
# digest::digest() on a data frame hashes R's serialization of the object, so
# it depends on things that are not the data (attribute order, the tibble
# subclass, the serialization version) while depending on representation
# details for things that are. This hash is defined over the values instead:
# column order, column names, declared class, and every value in a documented
# textual form. It is versioned so a deliberate change to the encoding shows
# up in the receipt rather than silently changing every hash.
#
# This is NOT the export-file hash. Export bundles hash file bytes, because
# what is attested there is the artefact a human received. Here the subject is
# the data, which must hash the same whether or not it was written to disk.
# ---------------------------------------------------------------------------

generator_data_hash_algorithm <- function() {
  "dataganger-canonical-data-v1"
}

generator_data_hash_double <- function(value) {
  if (value == 0) value <- 0
  bytes <- writeBin(value, raw(), size = 8L, endian = "big")
  paste(sprintf("%02x", as.integer(bytes)), collapse = "")
}

# NA must not collide with the literal string "NA", so missing values carry a
# separate flag and their text is emptied.
generator_data_hash_atomic <- function(value) {
  if (is.double(value)) {
    text <- vapply(value, function(item) {
      if (is.nan(item)) {
        "NaN"
      } else if (is.na(item)) {
        ""
      } else if (is.infinite(item)) {
        if (item > 0) "Inf" else "-Inf"
      } else {
        generator_data_hash_double(item)
      }
    }, character(1L))
  } else {
    text <- as.character(value)
  }
  missing <- is.na(value) & !is.nan(value)
  text[missing] <- ""
  list(
    missing = as.logical(missing),
    text = enc2utf8(as.character(text))
  )
}

generator_data_hash_column <- function(column) {
  if (is.factor(column)) {
    return(list(
      class = as.character(class(column)),
      levels = enc2utf8(as.character(levels(column))),
      values = generator_data_hash_atomic(as.character(column))
    ))
  }
  if (inherits(column, "Date")) {
    return(list(
      class = as.character(class(column)),
      values = generator_data_hash_atomic(as.numeric(column))
    ))
  }
  if (inherits(column, "POSIXct")) {
    timezone <- attr(column, "tzone", exact = TRUE)
    return(list(
      class = as.character(class(column)),
      timezone = if (is.null(timezone) || !length(timezone) ||
        !nzchar(timezone[[1L]])) {
        ""
      } else {
        as.character(timezone[[1L]])
      },
      values = generator_data_hash_atomic(as.numeric(column))
    ))
  }
  if (is.list(column)) {
    generator_unsafe_abort("A list column cannot be hashed as canonical data.")
  }
  list(
    class = as.character(class(column)),
    values = generator_data_hash_atomic(column)
  )
}

generator_data_hash <- function(data) {
  if (!is.data.frame(data)) {
    generator_unsafe_abort("A canonical data hash requires a data frame.")
  }
  bare <- as.data.frame(data, stringsAsFactors = FALSE)
  semantic_hash(list(
    algorithm = generator_data_hash_algorithm(),
    nrow = as.integer(nrow(bare)),
    ncol = as.integer(ncol(bare)),
    names = enc2utf8(as.character(names(bare))),
    columns = lapply(seq_len(ncol(bare)), function(index) {
      generator_data_hash_column(bare[[index]])
    })
  ))
}

# ---------------------------------------------------------------------------
# Contract policy derived from a fitted generator
#
# freeze_synthesis() and the store's approval boundary both derive the policy
# from this one function, so an approval can be checked against the generator
# it claims to describe instead of trusting the contract it was handed.
# ---------------------------------------------------------------------------

generator_derive_columns <- function(generator) {
  roles <- generator$roles
  columns <- lapply(names(generator$columns), function(name) {
    state <- generator$columns[[name]]
    row <- match(name, roles$variable)
    list(
      name = name,
      output_name = name,
      kind = state$kind,
      storage = state$storage %||% "character",
      role = if (is.na(row)) "unknown" else roles$recommended_role[[row]],
      user_role = if (is.na(row)) NA_character_ else roles$user_role[[row]],
      simulation = if (is.na(row)) NA_character_ else roles$simulation[[row]]
    )
  })
  columns <- columns[vapply(columns, function(column) {
    !identical(column$kind, "dropped")
  }, logical(1L))]
  strategy <- generator$settings$name_strategy %||% "preserve"
  output_names <- if (strategy %in% c("generic", "dictionary_only")) {
    paste0("col_", seq_along(columns))
  } else {
    vapply(columns, `[[`, character(1L), "name")
  }
  for (index in seq_along(columns)) {
    columns[[index]]$output_name <- output_names[[index]]
  }
  columns
}

generator_derive_policy <- function(generator) {
  columns <- generator_derive_columns(generator)
  generator_runtime_hashable(list(
    schema = columns,
    roles = generator_runtime_hashable(generator$roles),
    settings = generator_runtime_hashable(generator$settings),
    output_names = vapply(columns, `[[`, character(1L), "output_name")
  ))
}

generator_derive_compatibility <- function() {
  list(
    engine = "internal",
    package = "dataganger",
    package_version = as.character(utils::packageVersion("dataganger")),
    schema_version = generator_schema_version(),
    seed_algorithm = generator_seed_algorithm(),
    data_hash_algorithm = generator_data_hash_algorithm()
  )
}

validate_generator_named_object <- function(x, object) {
  if (!is.list(x) || length(x) == 0L || is.null(names(x))) {
    generator_schema_abort(sprintf("%s must be a non-empty named list.", object))
  }
  canonical_json(x)
  invisible(x)
}

#' Define bounded generation request limits
#'
#' Creates the approved ranges for seeds, output rows, and development
#' datasets used by a frozen generator contract.
#'
#' @param n Integer range of permitted output row counts.
#' @param datasets Integer range of permitted development dataset counts.
#' @param seed Integer range of permitted base seeds.
#'
#' @return An S3 object of class `dataganger_generation_limits`.
#' @export
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

#' Create or retrieve a frozen generator contract
#'
#' With policy, limits, and compatibility arguments, creates a validated
#' immutable public contract. When called with a `dataganger_frozen_generator`
#' handle, returns the contract already bound to that handle.
#'
#' @param policy A named list of approved policy fields, or a frozen generator
#'   handle.
#' @param allowed A `dataganger_generation_limits` object.
#' @param compatibility A named list of engine/compiler compatibility fields.
#' @param contract_version Semantic version for the public contract.
#' @param schema_version Contract schema version.
#' @return A `dataganger_contract` object.
#' @export
generator_contract <- function(policy,
                               allowed = NULL,
                               compatibility = NULL,
                               contract_version = "1.0.0",
                               schema_version = generator_schema_version()) {
  if (inherits(policy, "dataganger_frozen_generator")) {
    if (!is.null(allowed) || !is.null(compatibility) ||
      !identical(contract_version, "1.0.0") ||
      !identical(schema_version, generator_schema_version())) {
      generator_schema_abort(
        "A frozen generator handle cannot be combined with contract constructor arguments."
      )
    }
    generator_api_validate_frozen(policy)
    return(policy$contract)
  }
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
