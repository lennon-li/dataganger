# Internal state and persistence helpers for the reusable-generator workspace.

generator_workspace_default_store <- function() {
  file.path(
    tools::R_user_dir("dataganger", "data"),
    "generator-store-v1"
  )
}

generator_workspace_abort <- function(message, call = parent.frame()) {
  generator_abort(
    message,
    class = "dataganger_generator_workspace_error",
    call = call
  )
}

generator_workspace_state_get <- function(state, name) {
  if (is.environment(state) || inherits(state, "reactivevalues") || is.list(state)) {
    return(state[[name]])
  }
  generator_workspace_abort("Generator workspace state must be a reactiveValues object or named list.")
}

generator_workspace_state_set <- function(state, name, value) {
  if (inherits(state, "reactivevalues")) {
    .subset2(state, "impl")$set(name, value)
    return(state)
  }
  if (is.list(state)) {
    state[name] <- list(value)
    return(state)
  }
  generator_workspace_abort("Generator workspace state must be a reactiveValues object or named list.")
}

generator_workspace_state_confirmed <- function(value) {
  isTRUE(value) || (
    is.numeric(value) && length(value) == 1L && !is.na(value) && value >= 1
  )
}

generator_workspace_policy_token <- function(state) {
  digest::digest(
    list(
      source = if (is.data.frame(state$raw_data)) {
        generator_data_hash(state$raw_data)
      } else {
        NULL
      },
      roles = state$roles,
      spec = state$spec
    ),
    algo = "sha256"
  )
}

generator_workspace_readiness <- function(state) {
  raw_data <- generator_workspace_state_get(state, "raw_data")
  roles <- generator_workspace_state_get(state, "roles")
  spec <- generator_workspace_state_get(state, "spec")
  stale <- generator_workspace_state_get(state, "stale")
  comparison <- generator_workspace_state_get(state, "comparison")
  privacy <- generator_workspace_state_get(state, "privacy")

  blockers <- character(0)
  if (!is.data.frame(raw_data) || nrow(raw_data) < 1L || ncol(raw_data) < 1L) {
    blockers <- c(blockers, "source data are required.")
  }
  if (!generator_workspace_state_confirmed(
    generator_workspace_state_get(state, "roles_confirmed")
  )) {
    blockers <- c(blockers, "column roles must be confirmed.")
  }
  if (is.null(roles) || !isTRUE(tryCatch(
    roles_ready_for_generation(roles),
    error = function(error) FALSE
  ))) {
    blockers <- c(blockers, "column roles must be ready for generation.")
  }
  if (!generator_workspace_state_confirmed(
    generator_workspace_state_get(state, "spec_confirmed")
  )) {
    blockers <- c(blockers, "the synthesis specification must be confirmed.")
  }
  if (!inherits(spec, "dataganger_spec") ||
    !identical(spec[["engine", exact = TRUE]], "internal")) {
    blockers <- c(
      blockers,
      "the synthesis specification must explicitly use engine = \"internal\"."
    )
  }
  review_stale <- isTRUE(stale[["comparison", exact = TRUE]]) ||
    isTRUE(stale[["synthesis", exact = TRUE]])
  if (is.null(comparison)) {
    blockers <- c(blockers, "a comparison review is required.")
  } else if (review_stale) {
    blockers <- c(blockers, "the comparison review is stale.")
  }
  if (is.null(privacy)) {
    blockers <- c(blockers, "a privacy review is required.")
  } else if (review_stale) {
    blockers <- c(blockers, "the privacy review is stale.")
  }
  if (isTRUE(generator_workspace_state_get(state, "generator_source_released"))) {
    blockers <- c(blockers, "source data were released from this app session.")
  }
  if (isTRUE(generator_workspace_state_get(state, "generator_busy"))) {
    blockers <- c(blockers, "the generator workspace is busy.")
  }

  list(
    ready = length(blockers) == 0L,
    blockers = unique(blockers),
    warnings = character(0)
  )
}

generator_workspace_export_spec <- function(frozen) {
  policy <- frozen$contract$policy %||% list()
  settings <- policy$settings %||% list()
  purpose <- as.character(settings$purpose %||% "development")[[1L]]
  args <- list(
    purpose = purpose,
    engine = "internal",
    acknowledge_risk = identical(purpose, "analytics")
  )
  for (name in c(
    "name_strategy", "k_anon", "rare_level_min_n", "preserve_missingness",
    "coarsen_dates", "merge_rare", "free_text_strategy"
  )) {
    if (!is.null(settings[[name]])) args[[name]] <- settings[[name]]
  }
  tryCatch(do.call(synth_spec, args), error = function(error) NULL)
}

generator_workspace_export_roles <- function(frozen) {
  roles <- frozen$contract$policy$roles %||% NULL
  if (!is.list(roles) || !length(roles)) return(NULL)
  result <- tryCatch(
    as.data.frame(roles, stringsAsFactors = FALSE, optional = TRUE),
    error = function(error) NULL
  )
  if (is.null(result)) return(NULL)
  for (name in names(result)) {
    if (is.character(result[[name]])) {
      result[[name]][result[[name]] == "<missing>"] <- NA_character_
    }
  }
  class(result) <- c("dataganger_roles", "data.frame")
  result
}

generator_workspace_privacy_flags <- function(privacy) {
  if (is.null(privacy)) return(NULL)
  if (is.data.frame(privacy)) return(privacy)
  if (!is.list(privacy)) return(NULL)

  blockers <- privacy$blockers
  if (is.data.frame(blockers)) return(blockers)
  if (!is.list(blockers) || !length(blockers)) {
    flags <- data.frame(
      variable = character(), flag = character(), recommendation = character(),
      severity = character(), stringsAsFactors = FALSE
    )
  } else if (all(c("code", "message", "column") %in% names(blockers))) {
    n <- max(length(blockers$code), length(blockers$message), length(blockers$column))
    code <- rep(as.character(blockers$code %||% "privacy"), length.out = n)
    message <- rep(as.character(blockers$message %||% code), length.out = n)
    column <- rep(as.character(blockers$column %||% ""), length.out = n)
    flags <- data.frame(
      variable = column,
      flag = message,
      recommendation = "Review this generated output before sharing.",
      severity = ifelse(code %in% c("exact_row_match", "kanonymity_infeasible"),
        "high", "medium"),
      stringsAsFactors = FALSE
    )
  } else {
    flags <- data.frame(
      variable = "generated output",
      flag = "A generation privacy check returned an unsupported detail shape.",
      recommendation = "Do not share until the output has been reviewed.",
      severity = "high",
      stringsAsFactors = FALSE
    )
  }
  attr(flags, "stage") <- "post"
  attr(flags, "exact_row_matches") <- as.integer(privacy$exact_match_count %||% 0L)
  flags
}

generator_workspace_path <- function(root = NULL) {
  if (is.null(root)) {
    root <- generator_workspace_default_store()
  }
  if (!is.character(root) || length(root) != 1L || is.na(root) || !nzchar(root)) {
    generator_workspace_abort("Generator workspace root must be one non-empty character path.")
  }
  normalizePath(root, mustWork = FALSE)
}

generator_workspace_handles_dir <- function(root, create = TRUE) {
  root <- generator_workspace_path(root)
  if (file.exists(root) && !dir.exists(root)) {
    generator_workspace_abort("Generator workspace root is not a directory.")
  }
  if (create && !dir.exists(root) && !dir.create(root, recursive = TRUE, mode = "0700")) {
    generator_workspace_abort("Could not create the generator workspace root.")
  }
  if (create) {
    generator_store_chmod(root, "0700")
  }
  handles <- file.path(root, "handles")
  if (create && !dir.exists(handles) && !dir.create(handles, mode = "0700")) {
    generator_workspace_abort("Could not create the generator handle directory.")
  }
  if (create) {
    generator_store_chmod(handles, "0700")
  }
  handles
}

generator_workspace_index_path <- function(root) {
  file.path(generator_workspace_handles_dir(root), "index.json")
}

generator_workspace_empty_index <- function() {
  list(
    format = "dataganger-generator-workspace",
    schema_version = 1L,
    handles = list()
  )
}

generator_workspace_read_index <- function(root) {
  index_path <- generator_workspace_index_path(root)
  if (!file.exists(index_path)) {
    return(generator_workspace_empty_index())
  }
  index <- tryCatch(
    jsonlite::fromJSON(
      paste(readLines(index_path, warn = FALSE), collapse = ""),
      simplifyVector = FALSE
    ),
    error = function(error) generator_workspace_abort("Generator workspace index is invalid JSON.")
  )
  expected <- c("format", "schema_version", "handles")
  validate_generator_fields(index, expected, "Generator workspace index")
  if (!identical(index$format, "dataganger-generator-workspace") ||
    !identical(as.integer(index$schema_version), 1L) ||
    !is.list(index$handles)) {
    generator_workspace_abort("Generator workspace index schema is unsupported.")
  }
  index$handles <- lapply(index$handles, function(entry) {
    validate_generator_fields(
      entry,
      c("contract_id", "schema_version", "saved_at"),
      "Generator workspace handle metadata"
    )
    generator_store_valid_id(entry$contract_id, "Contract ID")
    if (!identical(as.integer(entry$schema_version), 1L) ||
      !is.character(entry$saved_at) || length(entry$saved_at) != 1L ||
      is.na(entry$saved_at) || !nzchar(entry$saved_at)) {
      generator_workspace_abort("Generator workspace handle metadata is invalid.")
    }
    list(
      contract_id = entry$contract_id,
      schema_version = 1L,
      saved_at = entry$saved_at
    )
  })
  index
}

generator_workspace_write_index <- function(root, index) {
  index_path <- generator_workspace_index_path(root)
  text <- jsonlite::toJSON(index, auto_unbox = TRUE, null = "null", pretty = FALSE)
  generator_store_atomic_write(index_path, as.character(text))
  invisible(index_path)
}

generator_workspace_handle_path <- function(root, contract_id) {
  if (!is.character(contract_id) || length(contract_id) != 1L ||
    is.na(contract_id) || !grepl("^[0-9a-f]{64}$", contract_id)) {
    generator_workspace_abort("Contract ID must be a lowercase opaque SHA-256 ID.")
  }
  file.path(
    generator_workspace_handles_dir(root),
    paste0(contract_id, ".rds")
  )
}

generator_workspace_atomic_save_rds <- function(value, path) {
  parent <- dirname(path)
  temporary <- tempfile(".dataganger-handle-", tmpdir = parent, fileext = ".tmp")
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  ok <- tryCatch({
    saveRDS(value, temporary, version = 3L)
    generator_store_chmod(temporary, "0600")
    file.rename(temporary, path)
  }, error = function(error) FALSE)
  if (!isTRUE(ok)) {
    generator_workspace_abort("Atomic generator handle write failed.")
  }
  generator_store_chmod(path, "0600")
  invisible(path)
}

generator_workspace_save_handle <- function(frozen, root = NULL) {
  validated <- generator_api_validate_frozen(frozen)
  root <- generator_workspace_path(root)
  handle_path <- generator_workspace_handle_path(root, validated$frozen$contract_id)
  generator_workspace_atomic_save_rds(validated$frozen, handle_path)

  index <- generator_workspace_read_index(root)
  contract_id <- validated$frozen$contract_id
  entries <- Filter(
    function(entry) !identical(entry$contract_id, contract_id),
    index$handles
  )
  entry <- list(
    contract_id = contract_id,
    schema_version = 1L,
    saved_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  index$handles <- c(entries, list(entry))
  index$handles <- index$handles[order(
    vapply(index$handles, `[[`, character(1L), "contract_id"),
    method = "radix"
  )]
  generator_workspace_write_index(root, index)
  entry
}

generator_workspace_list_handles <- function(root = NULL) {
  root <- generator_workspace_path(root)
  handles_dir <- generator_workspace_handles_dir(root, create = FALSE)
  if (!dir.exists(handles_dir)) {
    return(list())
  }
  generator_workspace_read_index(root)$handles
}

generator_workspace_load_handle <- function(contract_id, root = NULL) {
  root <- generator_workspace_path(root)
  handle_path <- generator_workspace_handle_path(root, contract_id)
  if (!file.exists(handle_path)) {
    generator_workspace_abort("No saved generator handle exists for this contract ID.")
  }
  frozen <- tryCatch(
    readRDS(handle_path),
    error = function(error) generator_workspace_abort("Saved generator handle is not readable.")
  )
  validated <- generator_api_validate_frozen(frozen)
  if (!identical(validated$frozen$contract_id, contract_id)) {
    generator_workspace_abort("Saved generator handle contract ID does not match its filename.")
  }
  validated$frozen
}

generator_workspace_handle_approved <- function(frozen) {
  validated <- generator_api_validate_frozen(frozen)
  approval <- tryCatch(
    generator_store_read_approval(
      validated$store,
      validated$contract$contract_id
    ),
    error = function(error) NULL
  )
  if (is.null(approval) || !identical(approval$status, "approved")) {
    return(FALSE)
  }
  isTRUE(tryCatch({
    generator_store_validate_active_approval(
      validated$store,
      validated$contract$contract_id
    )
    TRUE
  }, error = function(error) FALSE))
}

generator_workspace_release_source <- function(state) {
  source_fields <- c(
    "upload_source", "raw_data", "filename", "profile", "roles",
    "roles_confirmed", "column_filter", "objective_confirmed", "spec",
    "spec_confirmed", "synthetic", "comparison", "compare_selected_var",
    "privacy", "seed_used", "generation_count",
    "attested_no_direct", "fail_safe_status", "fail_safe_flagged",
    "fail_safe_upload_token", "stale", "uploaded_data", "generated_roles",
    "k_anon", "kanon", "kanon_acknowledged", "kanon_escape_routes",
    "kanon_next_provenance", "pipeline_warnings", "generator_draft",
    "generator_error"
  )
  for (name in source_fields) {
    value <- NULL
    if (identical(name, "roles_confirmed") ||
      identical(name, "objective_confirmed") ||
      identical(name, "spec_confirmed") ||
      identical(name, "generation_count")) {
      value <- 0L
    } else if (identical(name, "attested_no_direct")) {
      value <- FALSE
    } else if (identical(name, "fail_safe_status")) {
      value <- "idle"
    } else if (identical(name, "fail_safe_flagged")) {
      value <- data.frame(
        variable = character(0), reason = character(0), stringsAsFactors = FALSE
      )
    } else if (identical(name, "stale")) {
      value <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    } else if (identical(name, "kanon_acknowledged")) {
      value <- FALSE
    } else if (identical(name, "pipeline_warnings")) {
      value <- character(0)
    }
    state <- generator_workspace_state_set(state, name, value)
  }
  state <- generator_workspace_state_set(state, "generator_busy", FALSE)
  generator_workspace_state_set(state, "generator_source_released", TRUE)
}

generator_workspace_reset <- function(state) {
  values <- list(
    generator_draft = NULL,
    generator_draft_token = NULL,
    generator_active = NULL,
    generator_approval = NULL,
    generator_export_spec = NULL,
    generator_export_roles = NULL,
    generator_export_privacy = NULL,
    generator_result = NULL,
    generator_receipts = list(),
    generator_error = NULL,
    generator_busy = FALSE,
    generator_source_released = FALSE,
    generator_store_root = generator_workspace_default_store()
  )
  for (name in names(values)) {
    state <- generator_workspace_state_set(state, name, values[[name]])
  }
  state
}
