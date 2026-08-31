# Internal private store for fitted generators and lifecycle records.
#
# A private filesystem path is not a structural isolation boundary when an
# Agent and this trusted runner use the same operating-system account. Agent
# mode must add host-enforced process and filesystem capabilities later.

generator_store_schema_version <- function() {
  1L
}

generator_store_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_store_error",
    call = call
  )
}

generator_store_tamper_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_store_tamper_error",
    call = call
  )
}

generator_store_id <- function() {
  key <- generator_fit_csprng_key(32L)
  if (is.null(key)) {
    generator_store_abort(
      "The trusted cryptographic random source is unavailable; cannot create an opaque store ID."
    )
  }
  digest::digest(key, algo = "sha256")
}

generator_store_valid_id <- function(value, field = "ID") {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
    !grepl("^[0-9a-f]{64}$", value)) {
    generator_store_abort(sprintf("%s must be a lowercase opaque SHA-256 ID.", field))
  }
  invisible(value)
}

generator_store_dirs <- function() {
  c("contracts", "generators", "approvals", "receipts")
}

generator_store_marker_path <- function(root) {
  file.path(root, ".dataganger-private-store.json")
}

generator_store_object_path <- function(store, kind, id) {
  generator_store_valid_id(id, sprintf("%s ID", kind))
  if (!kind %in% generator_store_dirs()) {
    generator_store_abort(sprintf("Unknown private store object kind: %s.", kind))
  }
  file.path(store$root, kind, paste0(id, ".json"))
}

generator_store_chmod <- function(path, mode) {
  try(Sys.chmod(path, mode = mode), silent = TRUE)
  invisible(path)
}

generator_store_atomic_write <- function(path, text) {
  parent <- dirname(path)
  if (!dir.exists(parent)) {
    generator_store_abort("Private store object directory is missing.")
  }
  temporary <- tempfile(".dataganger-write-", tmpdir = parent, fileext = ".tmp")
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  ok <- tryCatch({
    writeLines(text, temporary, useBytes = TRUE)
    generator_store_chmod(temporary, "0600")
    file.rename(temporary, path)
  }, error = function(error) FALSE)
  if (!isTRUE(ok)) {
    generator_store_abort("Atomic private-store write failed; no approved object was changed.")
  }
  generator_store_chmod(path, "0600")
  invisible(path)
}

generator_store_encode <- function(value) {
  if (is.null(value)) {
    return(list(type = "null"))
  }

  if (is.object(value)) {
    classes <- class(value)
    allowed <- c(
      "dataganger_generator", "dataganger_generator_risk_report",
      "dataganger_contract", "dataganger_generation_limits"
    )
    if (any(!classes %in% allowed)) {
      generator_store_abort("Private store content contains an unsupported class.")
    }
    return(list(
      type = "object",
      class = as.character(classes),
      value = generator_store_encode(unclass(value))
    ))
  }

  if (is.raw(value)) {
    return(list(
      type = "raw",
      value = paste(sprintf("%02x", as.integer(value)), collapse = "")
    ))
  }

  if (is.list(value)) {
    return(list(
      type = "list",
      names = names(value),
      values = lapply(value, generator_store_encode)
    ))
  }

  if (!is.atomic(value) || is.complex(value) || is.object(value)) {
    generator_store_abort("Private store content contains an unsafe value.")
  }

  values <- lapply(seq_along(value), function(index) {
    item <- value[[index]]
    if (is.na(item)) {
      list(missing = TRUE)
    } else {
      list(missing = FALSE, value = unname(item))
    }
  })
  list(
    type = "atomic",
    storage = typeof(value),
    names = names(value),
    values = values
  )
}

generator_store_decode_names <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }
  value <- as.character(unlist(value, use.names = FALSE))
  if (!length(value)) NULL else value
}

generator_store_decode <- function(value) {
  if (!is.list(value) || is.null(value$type) || length(value$type) != 1L) {
    generator_store_tamper_abort("Private store payload has an invalid tagged value.")
  }
  type <- as.character(value$type)
  if (identical(type, "null")) {
    return(NULL)
  }
  if (identical(type, "raw")) {
    hex <- as.character(value$value %||% "")
    if (!nzchar(hex) || nchar(hex) %% 2L != 0L ||
      !grepl("^[0-9a-f]+$", hex)) {
      generator_store_tamper_abort("Private store raw payload is invalid.")
    }
    bytes <- strtoi(substring(hex, seq(1L, nchar(hex), by = 2L),
      seq(2L, nchar(hex), by = 2L)), base = 16L)
    return(as.raw(bytes))
  }
  if (identical(type, "list")) {
    values <- value$values
    if (!is.list(values)) {
      generator_store_tamper_abort("Private store list payload is invalid.")
    }
    result <- lapply(values, generator_store_decode)
    names(result) <- generator_store_decode_names(value$names)
    return(result)
  }
  if (identical(type, "object")) {
    classes <- as.character(unlist(value$class, use.names = FALSE))
    if (!length(classes)) {
      generator_store_tamper_abort("Private store object class is missing.")
    }
    result <- generator_store_decode(value$value)
    return(structure(result, class = classes))
  }
  if (!identical(type, "atomic")) {
    generator_store_tamper_abort("Private store payload has an unknown value type.")
  }

  storage <- as.character(value$storage)
  if (length(storage) != 1L || !storage %in% c("logical", "integer", "double", "character")) {
    generator_store_tamper_abort("Private store atomic payload has an invalid storage type.")
  }
  items <- value$values
  if (!is.list(items)) {
    generator_store_tamper_abort("Private store atomic payload is invalid.")
  }
  decoded <- lapply(items, function(item) {
    if (!is.list(item) || length(item$missing) != 1L) {
      generator_store_tamper_abort("Private store atomic item is invalid.")
    }
    if (isTRUE(item$missing)) return(NA)
    item$value
  })
  result <- switch(storage,
    logical = as.logical(unlist(decoded, use.names = FALSE)),
    integer = as.integer(unlist(decoded, use.names = FALSE)),
    double = as.numeric(unlist(decoded, use.names = FALSE)),
    character = as.character(unlist(decoded, use.names = FALSE))
  )
  if (length(items) == 0L) {
    result <- switch(storage,
      logical = logical(), integer = integer(), double = double(), character = character()
    )
  }
  names(result) <- generator_store_decode_names(value$names)
  result
}

generator_store_metadata <- function(metadata) {
  if (is.null(metadata)) return(NULL)
  if (!is.list(metadata) || is.null(names(metadata)) ||
    anyNA(names(metadata)) || any(!nzchar(names(metadata))) || anyDuplicated(names(metadata))) {
    generator_store_abort("Private store metadata must be a uniquely named list.")
  }
  generator_store_encode(metadata)
}

generator_store_envelope <- function(store, kind, id, value, metadata = NULL) {
  payload <- generator_store_encode(value)
  list(
    format = "dataganger-private-object",
    schema_version = generator_store_schema_version(),
    store_id = store$store_id,
    object_type = kind,
    object_id = id,
    payload_hash = semantic_hash(payload),
    payload = payload,
    metadata = generator_store_metadata(metadata)
  )
}

generator_store_write_object <- function(store, kind, id, value, metadata = NULL) {
  path <- generator_store_object_path(store, kind, id)
  envelope <- generator_store_envelope(store, kind, id, value, metadata)
  text <- jsonlite::toJSON(envelope, auto_unbox = TRUE, null = "null", pretty = FALSE, digits = NA)
  generator_store_atomic_write(path, as.character(text))
  invisible(path)
}

generator_store_read_object <- function(store, kind, id) {
  path <- generator_store_object_path(store, kind, id)
  if (!file.exists(path)) {
    generator_store_abort(sprintf("No %s exists for opaque ID %s.", kind, id))
  }
  envelope <- tryCatch(
    jsonlite::fromJSON(paste(readLines(path, warn = FALSE), collapse = ""), simplifyVector = FALSE),
    error = function(error) generator_store_tamper_abort("Private store object is not valid JSON.")
  )
  expected <- c("format", "schema_version", "store_id", "object_type", "object_id",
    "payload_hash", "payload", "metadata")
  validate_generator_fields(envelope, expected, sprintf("Private %s envelope", kind), generator_store_tamper_abort)
  if (!identical(envelope$format, "dataganger-private-object") ||
    !identical(as.integer(envelope$schema_version), generator_store_schema_version()) ||
    !identical(envelope$store_id, store$store_id) ||
    !identical(envelope$object_type, kind) || !identical(envelope$object_id, id)) {
    generator_store_tamper_abort("Private store object identity or schema does not match its path.")
  }
  validate_generator_hash(envelope$payload_hash, "private payload_hash")
  if (!identical(envelope$payload_hash, semantic_hash(envelope$payload))) {
    generator_store_tamper_abort("Private store payload integrity check failed.")
  }
  list(
    value = generator_store_decode(envelope$payload),
    metadata = if (is.null(envelope$metadata)) NULL else generator_store_decode(envelope$metadata),
    path = path
  )
}

generator_store_validate <- function(store) {
  if (!identical(attr(store, "class", exact = TRUE), "dataganger_generator_store") ||
    !is.list(store) || !dir.exists(store$root)) {
    generator_store_abort("Private store must be a DataGangeR-created store object.")
  }
  marker <- generator_store_marker_path(store$root)
  if (!file.exists(marker)) {
    generator_store_abort("Private store marker is missing.")
  }
  value <- tryCatch(
    jsonlite::fromJSON(paste(readLines(marker, warn = FALSE), collapse = ""), simplifyVector = FALSE),
    error = function(error) generator_store_tamper_abort("Private store marker is invalid JSON.")
  )
  if (!identical(value$format, "dataganger-private-store") ||
    !identical(as.integer(value$schema_version), generator_store_schema_version()) ||
    !identical(value$store_id, store$store_id)) {
    generator_store_tamper_abort("Private store marker does not match the store object.")
  }
  generator_store_valid_id(value$store_id, "Store ID")
  invisible(store)
}

generator_store_create <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    generator_store_abort("Private store path must be one non-empty character path.")
  }
  path <- normalizePath(path, mustWork = FALSE)
  if (file.exists(path) && !dir.exists(path)) {
    generator_store_abort("Private store path is not a directory.")
  }
  if (!dir.exists(path)) {
    if (!dir.create(path, recursive = TRUE, mode = "0700")) {
      generator_store_abort("Could not create the private store directory.")
    }
  }
  generator_store_chmod(path, "0700")
  marker <- generator_store_marker_path(path)
  if (file.exists(marker)) {
    return(generator_store_open(path))
  }
  store_id <- generator_store_id()
  for (kind in generator_store_dirs()) {
    dir.create(file.path(path, kind), mode = "0700")
    generator_store_chmod(file.path(path, kind), "0700")
  }
  marker_value <- list(
    format = "dataganger-private-store",
    schema_version = generator_store_schema_version(),
    store_id = store_id
  )
  generator_store_atomic_write(
    marker,
    as.character(jsonlite::toJSON(marker_value, auto_unbox = TRUE, pretty = FALSE))
  )
  generator_store_open(path)
}

generator_store_open <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    generator_store_abort("Private store path must be one non-empty character path.")
  }
  path <- normalizePath(path, mustWork = FALSE)
  marker <- generator_store_marker_path(path)
  if (!file.exists(marker)) {
    generator_store_abort("Refuse to open a directory that is not a DataGangeR private store.")
  }
  value <- tryCatch(
    jsonlite::fromJSON(paste(readLines(marker, warn = FALSE), collapse = ""), simplifyVector = FALSE),
    error = function(error) generator_store_tamper_abort("Private store marker is invalid JSON.")
  )
  if (!identical(value$format, "dataganger-private-store") ||
    !identical(as.integer(value$schema_version), generator_store_schema_version()) ||
    !is.character(value$store_id) || length(value$store_id) != 1L) {
    generator_store_tamper_abort("Private store marker has an invalid schema.")
  }
  generator_store_valid_id(value$store_id, "Store ID")
  store <- structure(list(
    root = path,
    store_id = value$store_id,
    schema_version = as.integer(value$schema_version)
  ), class = "dataganger_generator_store")
  generator_store_validate(store)
  store
}

generator_private_store <- generator_store_create

generator_store_put_contract <- function(store, contract) {
  generator_store_validate(store)
  validate_generator_contract(contract)
  generator_store_write_object(store, "contracts", contract$contract_id, contract)
  invisible(contract$contract_id)
}

generator_store_read_contract <- function(store, contract_id) {
  generator_store_validate(store)
  generator_store_valid_id(contract_id, "Contract ID")
  record <- generator_store_read_object(store, "contracts", contract_id)
  contract <- record$value
  validate_generator_contract(contract)
  if (!identical(contract$contract_id, contract_id)) {
    generator_store_tamper_abort("Contract content does not match its opaque ID.")
  }
  contract
}

generator_store_generator_fingerprint <- function(generator) {
  validate_internal_generator(generator)
  index <- generator$exact_row_index
  semantic_hash(list(
    schema_version = generator$schema_version,
    engine = generator$engine,
    eligible = generator$eligible,
    columns = generator_runtime_hashable(generator$columns),
    roles = generator_runtime_hashable(generator$roles),
    settings = generator_runtime_hashable(generator$settings),
    risk_report = generator_runtime_hashable(unclass(generator$risk_report)),
    exact_row_index = list(
      algorithm = index$algorithm,
      source_n = index$source_n,
      fingerprints = sort(index$fingerprints, method = "radix"),
      key_digest = digest::digest(index$key, algo = "sha256")
    )
  ))
}

generator_store_put_generator <- function(store, generator, metadata = NULL) {
  generator_store_validate(store)
  validate_internal_generator(generator)
  if (!isTRUE(generator$eligible)) {
    generator_store_abort("Only an eligible fitted generator may enter the private store.")
  }
  id <- generator_store_id()
  fingerprint <- generator_store_generator_fingerprint(generator)
  generator_store_write_object(store, "generators", id, generator, metadata)
  structure(list(
    generator_id = id,
    generator_revision = generator_runtime_revision_id(generator),
    generator_fingerprint = fingerprint
  ), class = "dataganger_private_generator_record")
}

generator_store_read_generator <- function(store, generator_id) {
  generator_store_validate(store)
  generator_store_valid_id(generator_id, "Generator ID")
  record <- generator_store_read_object(store, "generators", generator_id)
  generator <- record$value
  validate_internal_generator(generator)
  generator
}

generator_store_read_generator_record <- function(store, generator_id) {
  generator_store_validate(store)
  generator_store_valid_id(generator_id, "Generator ID")
  record <- generator_store_read_object(store, "generators", generator_id)
  validate_internal_generator(record$value)
  list(
    generator = record$value,
    metadata = record$metadata,
    generator_revision = generator_runtime_revision_id(record$value),
    generator_fingerprint = generator_store_generator_fingerprint(record$value)
  )
}

generator_store_update_metadata <- function(store, generator_id, metadata) {
  record <- generator_store_read_generator_record(store, generator_id)
  generator_store_write_object(store, "generators", generator_id, record$generator, metadata)
  invisible(record$generator_fingerprint)
}

generator_store_replace_generator <- function(store, generator_id, generator, metadata = NULL) {
  generator_store_validate(store)
  generator_store_valid_id(generator_id, "Generator ID")
  current <- generator_store_read_generator_record(store, generator_id)
  validate_internal_generator(generator)
  if (!isTRUE(generator$eligible)) {
    generator_store_abort("Only an eligible fitted generator may enter the private store.")
  }
  replacement_fingerprint <- generator_store_generator_fingerprint(generator)
  if (length(list.files(file.path(store$root, "approvals"), pattern = "^[0-9a-f]{64}\\.json$"))) {
    for (contract_id in sub("\\.json$", "", list.files(file.path(store$root, "approvals")))) {
      approval <- tryCatch(generator_store_read_approval(store, contract_id), error = function(error) NULL)
      if (!is.null(approval) && identical(approval$generator_id, generator_id) &&
        identical(approval$status, "approved")) {
        generator_store_abort("Replacing an approved generator requires revocation and fresh approval.")
      }
    }
  }
  if (identical(current$generator_fingerprint, replacement_fingerprint)) {
    generator_store_update_metadata(store, generator_id, metadata)
    return(invisible(generator_id))
  }
  generator_store_write_object(store, "generators", generator_id, generator, metadata)
  invisible(generator_id)
}

generator_store_approval_path <- function(store, contract_id) {
  generator_store_object_path(store, "approvals", contract_id)
}

generator_store_compiler <- function() {
  list(
    package = "dataganger",
    version = as.character(utils::packageVersion("dataganger")),
    schema_version = generator_schema_version()
  )
}

generator_store_approval_binding <- function(approval) {
  fields <- approval[setdiff(names(approval), "binding_hash")]
  semantic_hash(generator_runtime_hashable(fields))
}

generator_store_validate_contract_generator <- function(contract, generator,
                                                         abort = generator_store_abort) {
  expected_policy <- canonicalize_generator_value(generator_derive_policy(generator))
  expected_compatibility <- canonicalize_generator_value(
    generator_derive_compatibility()
  )
  if (!identical(contract$policy, expected_policy)) {
    abort("Contract policy is not derived from the fitted generator.")
  }
  if (!identical(contract$compatibility, expected_compatibility)) {
    abort("Contract compatibility is not derived from this DataGangeR runtime.")
  }
  invisible(contract)
}

generator_store_approve <- function(store, contract, generator_id, approver,
                                    approved_at = Sys.time()) {
  generator_store_validate(store)
  if (is.character(contract)) {
    contract <- generator_store_read_contract(store, contract)
  } else {
    validate_generator_contract(contract)
  }
  generator_store_valid_id(generator_id, "Generator ID")
  if (!is.character(approver) || length(approver) != 1L || is.na(approver) ||
    !nzchar(trimws(approver))) {
    generator_store_abort("Approver must be one non-empty character identity.")
  }
  generator <- generator_store_read_generator_record(store, generator_id)
  generator_store_validate_contract_generator(contract, generator$generator)
  approval_path <- generator_store_approval_path(store, contract$contract_id)
  if (file.exists(approval_path)) {
    existing <- generator_store_read_approval(store, contract$contract_id)
    if (!identical(existing$status, "approved")) {
      generator_store_abort(sprintf(
        "Contract %s has terminal approval status %s; create a new contract before approval.",
        contract$contract_id, existing$status
      ))
    }
    if (!identical(existing$generator_id, generator_id) ||
      !identical(existing$generator_revision, generator$generator_revision) ||
      !identical(existing$generator_fingerprint, generator$generator_fingerprint)) {
      generator_store_abort(
        "An active approval for this contract is bound to a different fitted generator."
      )
    }
    generator_store_validate_active_approval(store, contract$contract_id)
    return(existing)
  }
  generator_store_put_contract(store, contract)
  risk_hash <- semantic_hash(generator_runtime_hashable(unclass(generator$generator$risk_report)))
  approved_at <- if (inherits(approved_at, "POSIXt")) {
    format(approved_at, tz = "UTC", usetz = TRUE)
  } else as.character(approved_at)
  if (length(approved_at) != 1L || is.na(approved_at) || !nzchar(approved_at)) {
    generator_store_abort("Approval time must be one non-empty timestamp.")
  }
  approval <- list(
    schema_version = generator_store_schema_version(),
    approval_id = generator_store_id(),
    contract_id = contract$contract_id,
    generator_id = generator_id,
    generator_revision = generator$generator_revision,
    generator_fingerprint = generator$generator_fingerprint,
    allowed = unclass(contract$allowed),
    risk_report_hash = risk_hash,
    compiler = generator_store_compiler(),
    approver = trimws(approver),
    approved_at = approved_at,
    status = "approved",
    revoked_at = NULL,
    superseded_by = NULL,
    reason = NULL,
    binding_hash = NULL
  )
  approval$binding_hash <- generator_store_approval_binding(approval)
  generator_store_write_object(store, "approvals", contract$contract_id, approval)
  approval
}

generator_store_read_approval <- function(store, contract_id) {
  generator_store_validate(store)
  generator_store_valid_id(contract_id, "Contract ID")
  record <- generator_store_read_object(store, "approvals", contract_id)
  approval <- record$value
  expected <- c("schema_version", "approval_id", "contract_id", "generator_id",
    "generator_revision", "generator_fingerprint", "allowed", "risk_report_hash",
    "compiler", "approver", "approved_at", "status", "revoked_at", "superseded_by",
    "reason", "binding_hash")
  validate_generator_fields(approval, expected, "Generator approval", generator_store_tamper_abort)
  if (!identical(approval$contract_id, contract_id) ||
    !approval$status %in% c("approved", "revoked", "superseded")) {
    generator_store_tamper_abort("Generator approval identity or status is invalid.")
  }
  validate_generator_schema_version(approval$schema_version, "Generator approval")
  generator_store_valid_id(approval$approval_id, "Approval ID")
  generator_store_valid_id(approval$generator_id, "Generator ID")
  validate_generator_hash(approval$generator_revision, "generator_revision")
  validate_generator_hash(approval$generator_fingerprint, "generator_fingerprint")
  validate_generator_hash(approval$risk_report_hash, "risk_report_hash")
  validate_generator_hash(approval$binding_hash, "binding_hash")
  if (!identical(approval$binding_hash, generator_store_approval_binding(approval))) {
    generator_store_tamper_abort("Generator approval binding integrity check failed.")
  }
  approval
}

generator_store_validate_active_approval <- function(store, contract_id) {
  contract <- generator_store_read_contract(store, contract_id)
  approval <- generator_store_read_approval(store, contract_id)
  if (!identical(approval$status, "approved")) {
    generator_store_abort(sprintf("Contract %s is not active: approval is %s.", contract_id, approval$status))
  }
  if (!identical(approval$allowed, unclass(contract$allowed))) {
    generator_store_tamper_abort("Approved request bounds do not match the current contract.")
  }
  generator <- generator_store_read_generator_record(store, approval$generator_id)
  if (!identical(approval$generator_revision, generator$generator_revision) ||
    !identical(approval$generator_fingerprint, generator$generator_fingerprint)) {
    generator_store_tamper_abort("Approved fitted generator has been replaced or changed.")
  }
  actual_risk_hash <- semantic_hash(generator_runtime_hashable(unclass(generator$generator$risk_report)))
  if (!identical(approval$risk_report_hash, actual_risk_hash)) {
    generator_store_tamper_abort("Approved generator risk report has changed.")
  }
  generator_store_validate_contract_generator(
    contract, generator$generator, generator_store_tamper_abort
  )
  if (!identical(approval$compiler, generator_store_compiler())) {
    generator_store_abort("Approved generator was fitted by an incompatible compiler version.")
  }
  list(contract = contract, approval = approval, generator = generator$generator)
}

generator_store_revoke <- function(store, contract_id, reason,
                                   revoked_at = Sys.time()) {
  active <- generator_store_validate_active_approval(store, contract_id)
  if (!is.character(reason) || length(reason) != 1L || is.na(reason) ||
    !nzchar(trimws(reason))) {
    generator_store_abort("Revocation reason must be one non-empty character value.")
  }
  revoked_at <- if (inherits(revoked_at, "POSIXt")) {
    format(revoked_at, tz = "UTC", usetz = TRUE)
  } else as.character(revoked_at)
  approval <- active$approval
  approval$status <- "revoked"
  approval$revoked_at <- revoked_at
  approval$reason <- trimws(reason)
  approval$binding_hash <- generator_store_approval_binding(approval)
  generator_store_write_object(store, "approvals", contract_id, approval)
  approval
}

generator_store_supersede <- function(store, contract_id, superseded_by) {
  active <- generator_store_validate_active_approval(store, contract_id)
  replacement <- generator_store_validate_active_approval(store, superseded_by)
  if (identical(contract_id, superseded_by)) {
    generator_store_abort("A contract cannot supersede itself.")
  }
  approval <- active$approval
  approval$status <- "superseded"
  approval$superseded_by <- superseded_by
  approval$reason <- sprintf("Superseded by contract %s.", superseded_by)
  approval$binding_hash <- generator_store_approval_binding(approval)
  generator_store_write_object(store, "approvals", contract_id, approval)
  invisible(replacement$approval$approval_id)
}

generator_store_receipt <- function(store, active, request, result, started_at) {
  outputs <- result$outputs
  output_hashes <- if (length(outputs)) {
    vapply(outputs, generator_data_hash, character(1L))
  } else character()
  request_receipt_id <- generator_store_id()
  output_receipt_ids <- if (length(outputs)) {
    vapply(outputs, function(output) generator_store_id(), character(1L))
  } else character()
  completed_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  output_receipts <- lapply(seq_along(outputs), function(index) {
    list(
      schema_version = generator_store_schema_version(),
      receipt_type = "output",
      receipt_id = output_receipt_ids[[index]],
      request_receipt_id = request_receipt_id,
      contract_id = active$contract$contract_id,
      approval_id = active$approval$approval_id,
      generator_id = active$approval$generator_id,
      generator_revision = active$approval$generator_revision,
      request_id = request$request_id,
      dataset = as.integer(index),
      n = as.integer(request$n),
      seed = as.integer(result$seeds[[index]]),
      output_hash = output_hashes[[index]],
      hash_algorithm = generator_data_hash_algorithm(),
      seed_algorithm = result$seed_algorithm,
      rng_kinds = result$rng_kinds,
      privacy = result$privacy[[index]],
      warnings = result$dataset_warnings[[index]],
      compiler = generator_store_compiler(),
      started_at = started_at,
      completed_at = completed_at
    )
  })
  request_receipt <- list(
    schema_version = generator_store_schema_version(),
    receipt_type = "request",
    receipt_id = request_receipt_id,
    contract_id = active$contract$contract_id,
    approval_id = active$approval$approval_id,
    generator_id = active$approval$generator_id,
    generator_revision = active$approval$generator_revision,
    request_id = request$request_id,
    request = list(seed = request$seed, n = request$n, datasets = request$datasets),
    seeds = result$seeds,
    usable = isTRUE(result$usable),
    output_receipt_ids = output_receipt_ids,
    output_hashes = output_hashes,
    hash_algorithm = generator_data_hash_algorithm(),
    seed_algorithm = result$seed_algorithm,
    rng_kinds = result$rng_kinds,
    privacy = result$privacy,
    warnings = result$warnings,
    blockers = result$blockers,
    compiler = generator_store_compiler(),
    started_at = started_at,
    completed_at = completed_at
  )
  list(request = request_receipt, outputs = output_receipts)
}

generator_store_generate <- function(store, contract_id, request = NULL,
                                     seed = NULL, n = NULL, datasets = 1L) {
  active <- generator_store_validate_active_approval(store, contract_id)
  request <- generator_runtime_request(
    active$generator, active$contract, request, seed, n, datasets
  )
  started_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  result <- generator_generate(
    active$generator,
    request = request,
    contract = active$contract
  )
  receipts <- generator_store_receipt(store, active, request, result, started_at)
  for (receipt in receipts$outputs) {
    generator_store_write_object(store, "receipts", receipt$receipt_id, receipt)
  }
  receipt <- receipts$request
  generator_store_write_object(store, "receipts", receipt$receipt_id, receipt)
  result$receipt_id <- receipt$receipt_id
  result$receipt_ids <- receipt$output_receipt_ids
  result$approval_id <- active$approval$approval_id
  result
}

generator_store_read_receipt <- function(store, receipt_id) {
  generator_store_validate(store)
  generator_store_valid_id(receipt_id, "Receipt ID")
  record <- generator_store_read_object(store, "receipts", receipt_id)
  receipt <- record$value
  if (!is.list(receipt) || !identical(receipt$receipt_id, receipt_id)) {
    generator_store_tamper_abort("Audit receipt identity does not match its opaque ID.")
  }
  receipt
}

generator_store_migrate_generator <- function(store, generator_id, generator,
                                              metadata = NULL) {
  current <- generator_store_read_generator_record(store, generator_id)
  validate_internal_generator(generator)
  replacement <- generator_store_generator_fingerprint(generator)
  if (!identical(current$generator_fingerprint, replacement)) {
    generator_store_abort(
      "Semantic fitted-state migration changes the generator fingerprint; store a new generator and obtain reapproval."
    )
  }
  generator_store_update_metadata(store, generator_id, metadata)
  invisible(generator_id)
}

store_generator <- generator_store_put_generator
load_private_generator <- generator_store_read_generator
approve_generator_store <- generator_store_approve
