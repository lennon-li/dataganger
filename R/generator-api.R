#' Freeze a supported synthesis policy for repeated generation
#'
#' Fits the dependency-free internal generator while the source data are in a
#' human-controlled session, writes the fitted state to a private store, and
#' returns a source-free handle containing the public contract and opaque
#' references. The fitted state is not included in the returned object.
#'
#' @param data A data frame to use during the one-time fitting operation.
#' @param spec A `dataganger_spec` created by [synth_spec()] with
#'   `engine = "internal"`.
#' @param roles A `dataganger_roles` object. If `NULL`, roles are detected from
#'   `data` before fitting.
#' @param allowed A `dataganger_generation_limits` object defining permitted
#'   seed, row-count, and dataset-count ranges.
#' @param store A persistent private store path or an existing private store
#'   object. It must be supplied explicitly so the handle can be reopened in a
#'   later R session.
#'
#' @return A `dataganger_frozen_generator` handle. Save this handle with
#'   [saveRDS()] if it must be reopened in a later R session.
#' @export
freeze_synthesis <- function(data, spec, roles = NULL,
                             allowed = generation_limits(), store = NULL) {
  if (!is.data.frame(data)) {
    generator_api_abort("data must be a data frame.")
  }
  if (!inherits(spec, "dataganger_spec")) {
    generator_api_abort("spec must be a dataganger_spec object.")
  }
  if (is.null(store)) {
    generator_api_abort(
      "store must be an explicit persistent private-store path or store object."
    )
  }
  if (is.null(roles)) {
    roles <- detect_roles(data)
  }
  if (!inherits(allowed, "dataganger_generation_limits")) {
    generator_api_abort("allowed must be a dataganger_generation_limits object.")
  }
  validate_generation_limits(allowed)

  generator <- fit_internal_generator(data, spec, roles)
  if (!isTRUE(generator$eligible)) {
    blockers <- generator$risk_report$blockers$code
    generator_abort(
      sprintf(
        "Synthesis policy is not eligible for a frozen generator: %s.",
        paste(unique(blockers), collapse = ", ")
      ),
      class = "dataganger_generator_ineligible_error"
    )
  }

  private_store <- generator_api_store(store)
  record <- generator_store_put_generator(private_store, generator)
  contract <- generator_contract(
    policy = generator_derive_policy(generator),
    allowed = allowed,
    compatibility = generator_derive_compatibility()
  )
  generator_store_put_contract(private_store, contract)

  structure(
    list(
      schema_version = generator_schema_version(),
      contract = contract,
      contract_id = contract$contract_id,
      generator_id = record$generator_id,
      generator_revision = record$generator_revision,
      generator_fingerprint = record$generator_fingerprint,
      store = list(
        root = private_store$root,
        store_id = private_store$store_id,
        schema_version = private_store$schema_version
      ),
      risk_report = generator$risk_report
    ),
    class = "dataganger_frozen_generator"
  )
}

#' Return the fitting risk report for a frozen generator
#'
#' @param frozen A `dataganger_frozen_generator` handle.
#' @return A `dataganger_generator_risk_report` object.
#' @export
generator_risk_report <- function(frozen) {
  generator_api_validate_frozen(frozen)$risk_report
}

#' Approve a frozen generator for bounded generation
#'
#' Approval is recorded in the private store and binds the public contract,
#' fitted generator revision, request limits, compiler version, and risk
#' report. Generation remains unavailable until this function succeeds.
#'
#' @param frozen A `dataganger_frozen_generator` handle.
#' @param approved_contract_id Optional contract ID to approve. If `NULL`, the
#'   handle's contract ID is used.
#' @param approver One non-empty human identity recorded in the approval.
#'
#' @return An approved `dataganger_approval` object, invisibly.
#' @export
approve_generator <- function(frozen, approved_contract_id = NULL,
                              approver = Sys.info()[["user"]]) {
  validated <- generator_api_validate_frozen(frozen)
  contract_id <- approved_contract_id %||% validated$contract$contract_id
  generator_store_valid_id(contract_id, "Approved contract ID")
  if (!identical(contract_id, validated$contract$contract_id)) {
    generator_abort(
      "approved_contract_id does not match the frozen generator contract.",
      class = "dataganger_generator_error"
    )
  }
  approval <- generator_store_approve(
    validated$store,
    validated$contract,
    validated$frozen$generator_id,
    approver = approver
  )
  invisible(structure(approval, class = "dataganger_approval"))
}

#' Revoke an approved frozen generator
#'
#' Revocation is terminal for the current contract ID. A later approval must
#' use a newly reviewed contract. Revocation is not deletion: fitted state and
#' exact-row material remain in the private store. Use [destroy_generator()]
#' to permanently remove fitted state while retaining the contract, lifecycle
#' tombstone, and audit receipts.
#'
#' @param frozen A `dataganger_frozen_generator` handle.
#' @param reason One non-empty revocation reason.
#' @return A sanitized revocation record, invisibly.
#' @export
revoke_generator <- function(frozen, reason) {
  validated <- generator_api_validate_frozen(frozen)
  approval <- generator_store_revoke(
    validated$store, validated$contract$contract_id, reason
  )
  invisible(structure(list(
    contract_id = approval$contract_id,
    status = approval$status,
    revoked_at = approval$revoked_at,
    reason = approval$reason
  ), class = "dataganger_revocation"))
}

#' Permanently destroy fitted state for a frozen-generator contract
#'
#' The contract file is retained as a tombstone of the policy that existed.
#' The approval record is retained and marked `destroyed`, keeping the original
#' `approver` so it stays clear who approved the generator; `revoked_at` records
#' when it was destroyed and `reason` records who destroyed it and why.
#' Generation receipts are also retained as an audit trail. All fitted
#' generator records matching the contract, including their exact-row index,
#' are removed. Destruction is idempotent and a destroyed contract cannot be
#' recovered or used for generation.
#'
#' Destruction unlinks the fitted state from the private store. It is not a
#' secure wipe: on a journalling filesystem, an SSD with wear levelling, a
#' snapshotted volume, or any backup of the store, residual copies may survive
#' outside this package's control. Treat it as "removed from the store and
#' permanently unusable", not as forensic erasure.
#'
#' @param store A private store path or `dataganger_generator_store` object.
#' @param contract_id The opaque contract ID to destroy.
#' @param reason One non-empty destruction reason recorded in the tombstone.
#' @return A destruction tombstone, invisibly, including `generator_ids` for
#'   every fitted generator removed. A contract is keyed by its policy rather
#'   than by the source data, so one contract can hold several fitted
#'   generators compiled from different datasets; all of them are destroyed.
#' @export
destroy_generator <- function(store, contract_id, reason) {
  private_store <- generator_api_store(store)
  approval <- generator_store_destroy(private_store, contract_id, reason)
  invisible(structure(list(
    contract_id = approval$contract_id,
    status = approval$status,
    destroyed_at = approval$revoked_at,
    reason = approval$reason,
    generator_ids = attr(approval, "destroyed_generator_ids", exact = TRUE)
  ), class = "dataganger_destruction"))
}

#' Generate one or more approved synthetic datasets
#'
#' Generates one independent development variation for each requested dataset
#' count. One dataset is returned directly; multiple datasets are returned as a
#' `dataganger_batch` with deterministic seeds and audit provenance.
#'
#' @param frozen An approved `dataganger_frozen_generator` handle.
#' @param seed Optional scalar base seed within the approved range.
#' @param n Optional output row count within the approved range.
#' @param datasets Optional number of development variations within the
#'   approved range.
#'
#' @return A `dataganger_synthetic` data frame when `datasets = 1`, otherwise
#'   a `dataganger_batch`.
#' @export
generate_synthetic <- function(frozen, seed = NULL, n = NULL, datasets = 1L) {
  validated <- generator_api_validate_frozen(frozen)
  result <- generator_store_generate(
    validated$store,
    validated$contract$contract_id,
    seed = seed,
    n = n,
    datasets = datasets
  )
  if (!isTRUE(result$usable)) {
    codes <- unique(unlist(lapply(result$blockers, `[[`, "code"), use.names = FALSE))
    generator_abort(
      sprintf(
        paste0(
          "Generation failed a privacy check; no usable output was returned: %s. ",
          "The durable request receipt ID is %s."
        ),
        paste(codes, collapse = ", "), result$receipt_id
      ),
      class = "dataganger_generator_privacy_error",
      receipt_id = result$receipt_id
    )
  }
  request_receipt <- generator_store_read_receipt(validated$store, result$receipt_id)
  output_receipts <- lapply(result$receipt_ids, function(receipt_id) {
    generator_store_read_receipt(validated$store, receipt_id)
  })
  provenance <- generator_api_provenance(result, request_receipt, output_receipts)
  outputs <- Map(function(output, receipt, row) {
    public_receipt <- generator_api_public_receipt(receipt)
    attr(output, "generation_provenance") <- row
    attr(output, "generation_privacy") <- public_receipt$privacy
    attr(output, "generation_receipt") <- public_receipt
    output
  }, result$outputs, output_receipts, lapply(seq_len(nrow(provenance)), function(index) {
    provenance[index, , drop = FALSE]
  }))
  if (length(result$outputs) == 1L) {
    return(outputs[[1L]])
  }
  generator_batch(
    outputs = outputs,
    seeds = result$seeds,
    provenance = provenance,
    privacy = result$privacy,
    diagnostics = result$diagnostics,
    request_id = result$request_id,
    contract_id = result$contract_id,
    generator_revision = result$generator_revision,
    receipt_id = result$receipt_id,
    receipt_ids = result$receipt_ids
  )
}

#' Inspect a sanitized generation receipt
#'
#' @param x A generated dataset, generation batch, or frozen generator handle.
#' @param receipt_id For a frozen handle, an opaque request or output receipt
#'   ID. Omit this argument for generated datasets and batches.
#' @return A sanitized receipt, or a list of per-output receipts for a batch.
#' @export
generation_receipt <- function(x, receipt_id = NULL) {
  if (inherits(x, "dataganger_frozen_generator")) {
    if (is.null(receipt_id)) {
      generator_api_abort("receipt_id is required when x is a frozen generator.")
    }
    validated <- generator_api_validate_frozen(x)
    receipt <- generator_store_read_receipt(validated$store, receipt_id)
    if (!identical(receipt$contract_id, validated$contract$contract_id)) {
      generator_api_abort("Receipt does not belong to this frozen generator contract.")
    }
    return(generator_api_public_receipt(receipt))
  }
  if (inherits(x, "dataganger_batch")) {
    if (!is.null(receipt_id)) {
      generator_api_abort("receipt_id must be omitted for a generation batch.")
    }
    return(lapply(unclass(x)$datasets, function(output) {
      attr(output, "generation_receipt", exact = TRUE)
    }))
  }
  if (inherits(x, "dataganger_synthetic")) {
    if (!is.null(receipt_id)) {
      generator_api_abort("receipt_id must be omitted for a generated dataset.")
    }
    receipt <- attr(x, "generation_receipt", exact = TRUE)
    if (is.null(receipt)) generator_api_abort("Generated dataset has no audit receipt.")
    return(receipt)
  }
  generator_api_abort("x must be a frozen generator, generated dataset, or batch.")
}

#' @export
summary.dataganger_frozen_generator <- function(object, ...) {
  generator_api_validate_frozen_structure(object)
  validated <- tryCatch(
    generator_api_validate_frozen(object),
    dataganger_generator_store_error = function(error) NULL
  )
  structure(
    list(
      type = "dataganger_frozen_generator",
      contract_id = object$contract$contract_id,
      generator_id = object$generator_id,
      generator_revision = object$generator_revision,
      eligible = object$risk_report$eligible,
      store_available = !is.null(validated),
      approved = if (is.null(validated)) NA else generator_api_has_active_approval(validated)
    ),
    class = "summary_dataganger_frozen_generator"
  )
}

#' @export
print.summary_dataganger_frozen_generator <- function(x, ...) {
  cat("DataGangeR frozen generator\n")
  cat("  contract ID: ", x$contract_id, "\n", sep = "")
  cat("  generator ID: ", x$generator_id, "\n", sep = "")
  cat("  eligible: ", x$eligible, "\n", sep = "")
  cat("  store available: ", x$store_available, "\n", sep = "")
  cat("  approved: ", x$approved, "\n", sep = "")
  invisible(x)
}

#' @export
print.dataganger_frozen_generator <- function(x, ...) {
  print(summary(x), ...)
  invisible(x)
}

generator_api_abort <- function(message) {
  generator_abort(message, class = "dataganger_generator_error")
}

generator_api_store <- function(store) {
  if (inherits(store, "dataganger_generator_store")) {
    generator_store_validate(store)
    return(store)
  }
  if (is.null(store)) {
    generator_api_abort(
      "store must be an explicit persistent private-store path or store object."
    )
  }
  if (!is.character(store) || length(store) != 1L || is.na(store) || !nzchar(store)) {
    generator_api_abort("store must be a private store path or store object.")
  }
  generator_store_create(store)
}

generator_api_validate_frozen_structure <- function(frozen) {
  if (!identical(attr(frozen, "class", exact = TRUE), "dataganger_frozen_generator") ||
    !is.list(frozen)) {
    generator_api_abort("frozen must be a dataganger_frozen_generator handle.")
  }
  expected <- c(
    "schema_version", "contract", "contract_id", "generator_id",
    "generator_revision", "generator_fingerprint", "store", "risk_report"
  )
  validate_generator_fields(unclass(frozen), expected, "Frozen generator")
  validate_generator_schema_version(frozen$schema_version, "Frozen generator")
  validate_generator_contract(frozen$contract)
  validate_generator_hash(frozen$contract_id, "frozen contract_id")
  validate_generator_hash(frozen$generator_id, "frozen generator_id")
  validate_generator_hash(frozen$generator_revision, "frozen generator_revision")
  validate_generator_hash(frozen$generator_fingerprint, "frozen generator_fingerprint")
  validate_generator_risk_report(frozen$risk_report)
  if (!identical(frozen$contract_id, frozen$contract$contract_id)) {
    generator_tamper_abort("Frozen generator contract reference does not match its contract.")
  }
  if (!is.list(frozen$store) || is.null(frozen$store$root) ||
    !is.character(frozen$store$root) || length(frozen$store$root) != 1L) {
    generator_schema_abort("Frozen generator private store reference is invalid.")
  }
  validate_generator_fields(
    frozen$store,
    c("root", "store_id", "schema_version"),
    "Frozen generator private store reference"
  )
  validate_generator_hash(frozen$store$store_id, "frozen store_id")
  if (!generator_is_integerish(frozen$store$schema_version) ||
    length(frozen$store$schema_version) != 1L ||
    !identical(as.integer(frozen$store$schema_version), generator_store_schema_version())) {
    generator_schema_abort("Frozen generator private store schema is unsupported.")
  }
  invisible(frozen)
}

generator_api_validate_frozen <- function(frozen) {
  generator_api_validate_frozen_structure(frozen)
  store <- generator_store_open(frozen$store$root)
  if (!identical(store$store_id, frozen$store$store_id)) {
    generator_tamper_abort("Frozen generator store reference does not match its private store.")
  }
  approval_path <- generator_store_approval_path(store, frozen$contract_id)
  if (file.exists(approval_path) &&
      identical(generator_store_read_approval(store, frozen$contract_id)$status, "destroyed")) {
    generator_api_abort(sprintf(
      "Contract %s was destroyed; its fitted generator state is unavailable.",
      frozen$contract_id
    ))
  }
  record <- generator_store_read_generator_record(store, frozen$generator_id)
  if (!identical(record$generator_revision, frozen$generator_revision) ||
    !identical(record$generator_fingerprint, frozen$generator_fingerprint)) {
    generator_tamper_abort("Frozen generator handle does not match its stored generator.")
  }
  generator_store_validate_contract_generator(
    frozen$contract, record$generator, generator_tamper_abort
  )
  frozen_risk_hash <- semantic_hash(
    generator_runtime_hashable(unclass(frozen$risk_report))
  )
  stored_risk_hash <- semantic_hash(
    generator_runtime_hashable(unclass(record$generator$risk_report))
  )
  if (!identical(frozen_risk_hash, stored_risk_hash)) {
    generator_tamper_abort(
      "Frozen generator risk report does not match its stored generator."
    )
  }
  list(
    frozen = frozen,
    contract = frozen$contract,
    risk_report = frozen$risk_report,
    store = store
  )
}

generator_api_has_active_approval <- function(validated) {
  approval <- tryCatch(
    generator_store_read_approval(validated$store, validated$contract$contract_id),
    error = function(error) NULL
  )
  !is.null(approval) && identical(approval$status, "approved")
}

generator_api_public_receipt <- function(receipt) {
  allowed <- c(
    "schema_version", "receipt_type", "receipt_id", "request_receipt_id",
    "contract_id", "generator_revision", "request_id", "request", "dataset",
    "n", "seed", "seeds", "usable", "output_receipt_ids", "output_hash",
    "output_hashes", "hash_algorithm", "seed_algorithm", "rng_kinds",
    "privacy", "warnings", "blockers", "compiler", "started_at", "completed_at"
  )
  structure(receipt[intersect(allowed, names(receipt))],
    class = "dataganger_generation_receipt")
}

generator_api_provenance <- function(result, request_receipt, output_receipts) {
  privacy <- result$privacy
  kanon <- lapply(privacy, `[[`, "kanon")
  data.frame(
    dataset = seq_along(result$seeds),
    seed = as.integer(result$seeds),
    n = vapply(output_receipts, `[[`, integer(1L), "n"),
    output_hash = vapply(output_receipts, `[[`, character(1L), "output_hash"),
    hash_algorithm = vapply(output_receipts, `[[`, character(1L), "hash_algorithm"),
    receipt_id = vapply(output_receipts, `[[`, character(1L), "receipt_id"),
    request_receipt_id = rep(request_receipt$receipt_id, length(result$seeds)),
    privacy_ok = vapply(privacy, function(item) isTRUE(item$ok), logical(1L)),
    exact_match_count = vapply(privacy, function(item) {
      as.integer(item$exact_match_count %||% 0L)
    }, integer(1L)),
    suppressed_cells = vapply(kanon, function(item) {
      as.integer(item$suppressed_cells %||% 0L)
    }, integer(1L)),
    suppressed_rows = vapply(kanon, function(item) {
      as.integer(item$suppressed_rows %||% 0L)
    }, integer(1L)),
    suppressed_row_frac = vapply(kanon, function(item) {
      as.numeric(item$suppressed_row_frac %||% 0)
    }, numeric(1L)),
    kanon_infeasible = vapply(kanon, function(item) {
      isTRUE(item$infeasible)
    }, logical(1L)),
    stringsAsFactors = FALSE
  )
}

#' @keywords internal
#' @noRd
generator_api_recover_frozen_handle <- function(store, contract_id) {
  private_store <- generator_store_open(store)
  contract <- generator_store_read_contract(private_store, contract_id)

  approval_path <- generator_store_approval_path(private_store, contract_id)
  approval <- if (file.exists(approval_path)) {
    generator_store_read_approval(private_store, contract_id)
  } else {
    NULL
  }

  if (!is.null(approval) && identical(approval$status, "destroyed")) {
    generator_api_abort(sprintf(
      "Contract %s was destroyed; its fitted generator state cannot be recovered.",
      contract_id
    ))
  }

  if (!is.null(approval) && identical(approval$status, "approved")) {
    generator_store_validate_active_approval(private_store, contract_id)
  }

  generator_id <- if (!is.null(approval)) {
    approval$generator_id
  } else {
    generator_files <- list.files(
      file.path(private_store$root, "generators"),
      pattern = "^[0-9a-f]{64}\\.json$"
    )
    matches <- lapply(sub("\\.json$", "", generator_files), function(id) {
      record <- generator_store_read_generator_record(private_store, id)
      matches_contract <- tryCatch({
        generator_store_validate_contract_generator(contract, record$generator)
        TRUE
      }, error = function(error) FALSE)
      if (isTRUE(matches_contract)) record else NULL
    })
    matching_ids <- sub(
      "\\.json$", "", generator_files
    )[!vapply(matches, is.null, logical(1L))]
    if (length(matching_ids) != 1L) {
      generator_api_abort(sprintf(
        "Contract %s does not have exactly one stored generator.", contract_id
      ))
    }
    matching_ids[[1L]]
  }
  generator_record <- generator_store_read_generator_record(
    private_store, generator_id
  )

  frozen <- structure(
    list(
      schema_version = generator_schema_version(),
      contract = contract,
      contract_id = contract$contract_id,
      generator_id = generator_id,
      generator_revision = generator_record$generator_revision,
      generator_fingerprint = generator_record$generator_fingerprint,
      store = list(
        root = private_store$root,
        store_id = private_store$store_id,
        schema_version = private_store$schema_version
      ),
      risk_report = generator_record$generator$risk_report
    ),
    class = "dataganger_frozen_generator"
  )
  generator_api_validate_frozen(frozen)
  frozen
}
