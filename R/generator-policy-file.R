# Internal policy-file helpers for reusable generator setup.

generator_policy_format_version <- function() {
  1L
}

generator_policy_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_policy_file_error",
    call = call
  )
}

generator_policy_expected_fields <- function() {
  c("format_version", "created_at", "source_hash", "roles", "spec", "allowed")
}

generator_policy_validate_roles <- function(roles) {
  if (!is.data.frame(roles)) {
    generator_policy_abort("Generator policy roles must be a data frame.")
  }
  if (!("variable" %in% names(roles))) {
    generator_policy_abort("Generator policy roles must include a variable column.")
  }
  variables <- as.character(roles$variable)
  if (!length(variables) || anyNA(variables) || any(!nzchar(variables)) ||
    anyDuplicated(variables)) {
    generator_policy_abort(
      "Generator policy role variables must be non-empty and unique."
    )
  }
  roles
}

generator_policy_validate_object <- function(policy) {
  if (!inherits(policy, "dataganger_generator_policy")) {
    generator_policy_abort(
      "Generator policy file must inherit class dataganger_generator_policy."
    )
  }

  validate_generator_fields(
    unclass(policy),
    generator_policy_expected_fields(),
    "Generator policy file",
    abort = generator_policy_abort
  )

  version <- policy$format_version
  if (!generator_is_integerish(version) || length(version) != 1L) {
    generator_policy_abort("Generator policy format_version must be one integer.")
  }
  version <- as.integer(version[[1L]])
  supported_version <- generator_policy_format_version()
  if (!identical(version, supported_version)) {
    generator_policy_abort(sprintf(
      paste0(
        "Unsupported generator policy format version %s. ",
        "This DataGangeR build supports version %s."
      ),
      format(version),
      supported_version
    ))
  }

  created_at <- policy$created_at
  if (!is.character(created_at) || length(created_at) != 1L ||
    is.na(created_at) || !nzchar(created_at)) {
    generator_policy_abort(
      "Generator policy created_at must be one non-empty character timestamp."
    )
  }

  validate_generator_hash(policy$source_hash, "Generator policy source_hash")

  roles <- generator_policy_validate_roles(policy$roles)
  spec <- policy$spec
  if (!inherits(spec, "dataganger_spec")) {
    generator_policy_abort(
      "Generator policy spec must be a dataganger_spec object."
    )
  }
  if (!identical(spec[["engine", exact = TRUE]], "internal")) {
    generator_policy_abort(
      "Generator policy spec must explicitly use engine = \"internal\"."
    )
  }

  allowed <- policy$allowed
  validate_generation_limits(allowed)
  allowed <- generation_limits(
    seed = as.integer(allowed$seed),
    n = as.integer(allowed$n),
    datasets = as.integer(allowed$datasets)
  )

  structure(
    list(
      format_version = supported_version,
      created_at = created_at,
      source_hash = policy$source_hash,
      roles = roles,
      spec = spec,
      allowed = allowed
    ),
    class = "dataganger_generator_policy"
  )
}

generator_policy_allowed_from_state <- function(state) {
  allowed <- generator_workspace_state_get(state, "generator_policy_allowed")

  if (is.null(allowed)) {
    draft <- generator_workspace_state_get(state, "generator_draft")
    if (is.list(draft) && !inherits(draft, "dataganger_frozen_generator")) {
      allowed <- draft$allowed
    }
  }

  if (is.null(allowed)) {
    active <- generator_workspace_state_get(state, "generator_active")
    if (is.list(active) && is.list(active$contract)) {
      allowed <- active$contract$allowed
      if (is.null(allowed) && is.list(active$contract$policy)) {
        allowed <- active$contract$policy$allowed
      }
    }
  }

  if (is.null(allowed)) {
    allowed <- generation_limits()
  }

  validate_generation_limits(allowed)
  generation_limits(
    seed = as.integer(allowed$seed),
    n = as.integer(allowed$n),
    datasets = as.integer(allowed$datasets)
  )
}

#' @keywords internal
#' @noRd
save_generator_policy <- function(state, path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    generator_policy_abort("Policy file path must be one non-empty character string.")
  }

  raw_data <- generator_workspace_state_get(state, "raw_data")
  roles <- generator_workspace_state_get(state, "roles")
  spec <- generator_workspace_state_get(state, "spec")

  if (!is.data.frame(raw_data)) {
    generator_policy_abort("Source data are required before saving a policy.")
  }
  if (is.null(roles)) {
    generator_policy_abort("Column roles are required before saving a policy.")
  }
  if (!inherits(spec, "dataganger_spec")) {
    generator_policy_abort("A dataganger_spec object is required before saving a policy.")
  }
  if (!identical(spec[["engine", exact = TRUE]], "internal")) {
    generator_policy_abort(
      "Policy save requires spec engine = \"internal\"; non-internal specs are rejected."
    )
  }

  policy <- structure(
    list(
      format_version = generator_policy_format_version(),
      created_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      source_hash = generator_data_hash(raw_data),
      roles = roles,
      spec = spec,
      allowed = generator_policy_allowed_from_state(state)
    ),
    class = "dataganger_generator_policy"
  )
  policy <- generator_policy_validate_object(policy)

  ok <- tryCatch({
    saveRDS(policy, path, version = 3L)
    TRUE
  }, error = function(error) FALSE)
  if (!isTRUE(ok)) {
    generator_policy_abort("Saving the generator policy file failed.")
  }

  invisible(policy)
}

#' @keywords internal
#' @noRd
load_generator_policy <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    generator_policy_abort("Policy file path must be one non-empty character string.")
  }
  if (!file.exists(path)) {
    generator_policy_abort("Generator policy file does not exist.")
  }

  policy <- tryCatch(
    readRDS(path),
    error = function(error) {
      generator_policy_abort("Generator policy file is not a readable RDS object.")
    }
  )

  generator_policy_validate_object(policy)
}

#' @keywords internal
#' @noRd
generator_policy_matches_data <- function(policy, data) {
  validated <- generator_policy_validate_object(policy)
  if (!is.data.frame(data)) {
    return(FALSE)
  }
  hash <- tryCatch(generator_data_hash(data), error = function(error) NULL)
  identical(validated$source_hash, hash)
}
