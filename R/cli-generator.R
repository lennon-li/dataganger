cli_cmd_generator <- function(args) {
  if (length(args) == 0L || args[[1]] %in% c("-h", "--help")) {
    cli_print_generator_help()
    return(cli_status_ok())
  }

  subcmd <- args[[1]]
  rest <- args[-1]

  switch(
    subcmd,
    freeze = cli_cmd_generator_freeze(rest),
    inspect = cli_cmd_generator_inspect(rest),
    generate = cli_cmd_generator_generate(rest),
    revoke = cli_cmd_generator_revoke(rest),
    status = cli_cmd_generator_status(rest),
    {
      cli::cli_alert_danger("Unknown generator subcommand: {subcmd}")
      cli_status_usage()
    }
  )
}

#' Open an existing private store for a read-only generator subcommand
#'
#' Read-only subcommands must never create a private store. Creating one on a
#' mistyped `--store` path would report an empty but healthy store instead of
#' failing, so this opens an existing store and errors when none is present.
#'
#' @keywords internal
#' @noRd
cli_generator_open_store <- function(path) {
  if (!file.exists(generator_store_marker_path(normalizePath(path, mustWork = FALSE)))) {
    cli::cli_abort("No DataGangeR private store at {.path {path}}.")
  }
  generator_store_open(path)
}

cli_generator_read_approval <- function(store, contract_id) {
  path <- generator_store_approval_path(store, contract_id)
  if (!file.exists(path)) {
    return(NULL)
  }
  generator_store_read_approval(store, contract_id)
}

cli_generator_export_privacy <- function(synthetic) {
  privacy <- attr(synthetic, "generation_privacy", exact = TRUE)
  if (is.null(privacy)) {
    return(NULL)
  }
  blockers <- privacy$blockers
  if (is.list(blockers) && all(c("code", "message", "column") %in% names(blockers)) &&
      !length(blockers$code)) {
    return(NULL)
  }
  generator_workspace_privacy_flags(privacy)
}

cli_print_generator_help <- function() {
  cat(
    paste(
      "Usage: dataganger generator <command> [options]",
      "",
      "Commands:",
      "  freeze <data-file> --spec <spec.yaml> --store <dir> [--roles <roles.yaml>] [--max-n <int>] [--max-datasets <int>] [--out <file.json>]",
      "  inspect --store <dir> --contract-id <id> [--out <file.json>]",
      "  generate --store <dir> --contract-id <id> --out <path> [--seed <int>] [--n <int>] [--datasets <int>] [--acknowledge-kanon true|false] [--acknowledge-exact-match true|false]",
      "  revoke --store <dir> --contract-id <id> --reason <text>",
      "  status --store <dir> [--contract-id <id>] [--out <file.json>]",
      sep = "\n"
    ),
    "\n",
    sep = ""
  )
}

cli_cmd_generator_freeze <- function(args) {
  opts <- cli_parse_options(args, allowed = c("spec", "store", "roles", "max-n", "max-datasets", "out"))

  if (length(opts$positionals) != 1L) {
    cli_usage_error("generator freeze requires exactly one positional argument: <data-file>")
  }

  data_file <- opts$positionals[[1]]
  cli_assert_existing_file(data_file)
  spec_path <- cli_require_option(opts, "spec")
  cli_assert_existing_file(spec_path)
  store_path <- cli_require_option(opts, "store")

  roles_path <- opts$options$roles
  if (!is.null(roles_path)) {
    cli_assert_existing_file(roles_path)
  }

  max_n <- if (!is.null(opts$options[["max-n"]])) as.integer(opts$options[["max-n"]]) else NULL
  max_datasets <- if (!is.null(opts$options[["max-datasets"]])) as.integer(opts$options[["max-datasets"]]) else NULL

  data <- read_input(data_file)
  spec <- cli_read_spec_yaml(spec_path)
  roles <- if (!is.null(roles_path)) cli_read_roles_yaml(roles_path, data) else NULL

  limits_args <- list()
  if (!is.null(max_n)) limits_args$n <- c(1L, max_n)
  if (!is.null(max_datasets)) limits_args$datasets <- c(1L, max_datasets)
  allowed <- do.call(generation_limits, limits_args)

  frozen <- freeze_synthesis(data, spec, roles = roles, allowed = allowed, store = store_path)

  summary_obj <- summary(frozen)

  if (!is.null(opts$options$out)) {
    cli_write_json(unclass(summary_obj), opts$options$out)
  }

  cli::cli_h1("DataGangeR Frozen Generator")
  cli::cli_alert_success("Contract ID: {.val {summary_obj$contract_id}}")
  cli::cli_alert_info("Generator ID: {.val {summary_obj$generator_id}}")

  if (summary_obj$eligible) {
    cli::cli_alert_success("Generator is eligible for synthesis.")
  } else {
    cli::cli_alert_danger("Generator is NOT eligible. Review risk report for blockers.")
  }

  cli_status_ok()
}

cli_cmd_generator_inspect <- function(args) {
  opts <- cli_parse_options(args, allowed = c("store", "contract-id", "out"))
  if (length(opts$positionals) > 0L) {
    cli_usage_error("generator inspect takes no positional arguments")
  }

  store_path <- cli_require_option(opts, "store")
  contract_id <- cli_require_option(opts, "contract-id")

  private_store <- cli_generator_open_store(store_path)
  contract <- tryCatch(
    generator_store_read_contract(private_store, contract_id),
    error = function(e) {
      cli::cli_abort("Contract {.val {contract_id}} not found in store.")
    }
  )

  approval <- cli_generator_read_approval(private_store, contract_id)

  info <- list(
    contract_id = contract$contract_id,
    schema_version = contract$schema_version,
    contract_version = contract$contract_version,
    limits = unclass(contract$allowed),
    approval_status = if (is.null(approval)) "none" else approval$status,
    generator_id = if (is.null(approval)) NA_character_ else approval$generator_id
  )

  if (!is.null(opts$options$out)) {
    cli_write_json(info, opts$options$out)
  }

  cli::cli_h1("Generator Contract")
  cli::cli_alert_info("Contract ID: {.val {info$contract_id}}")
  cli::cli_alert_info("Approval status: {.val {info$approval_status}}")
  if (!is.na(info$generator_id)) {
    cli::cli_alert_info("Generator ID: {.val {info$generator_id}}")
  }

  cli_status_ok()
}

cli_cmd_generator_generate <- function(args) {
  opts <- cli_parse_options(args, allowed = c(
    "store", "contract-id", "out", "seed", "n", "datasets",
    "acknowledge-kanon", "acknowledge-exact-match"
  ))
  if (length(opts$positionals) > 0L) {
    cli_usage_error("generator generate takes no positional arguments")
  }

  store_path <- cli_require_option(opts, "store")
  contract_id <- cli_require_option(opts, "contract-id")
  out_path <- cli_require_option(opts, "out")

  seed <- if (!is.null(opts$options$seed)) as.integer(opts$options$seed) else NULL
  n <- if (!is.null(opts$options$n)) as.integer(opts$options$n) else NULL
  datasets <- if (!is.null(opts$options$datasets)) as.integer(opts$options$datasets) else 1L
  acknowledge_kanon <- if (!is.null(opts$options[["acknowledge-kanon"]])) {
    cli_parse_bool(opts$options[["acknowledge-kanon"]], "acknowledge-kanon")
  } else {
    FALSE
  }
  acknowledge_exact_match <- if (!is.null(opts$options[["acknowledge-exact-match"]])) {
    cli_parse_bool(
      opts$options[["acknowledge-exact-match"]], "acknowledge-exact-match"
    )
  } else {
    FALSE
  }

  frozen <- generator_api_recover_frozen_handle(store_path, contract_id)
  private_store <- generator_store_open(store_path)
  approval <- cli_generator_read_approval(private_store, contract_id)

  result <- tryCatch(
    generate_synthetic(frozen, seed = seed, n = n, datasets = datasets),
    dataganger_generator_error = function(e) {
      cli::cli_abort(conditionMessage(e))
    }
  )

  written <- generator_cli_write_generation(
    result = result,
    frozen = frozen,
    approval = approval,
    out_path = out_path,
    acknowledge_kanon = acknowledge_kanon,
    acknowledge_exact_match = acknowledge_exact_match
  )
  receipts <- written$receipts

  if (isTRUE(written$batch)) {
    cli::cli_alert_success("Wrote {length(receipts)} dataset bundles to {.path {out_path}}")
    cli::cli_alert_success("Generated {length(receipts)} datasets.")
    for (r in receipts) {
       cli::cli_alert_info("Receipt ID: {.val {r$receipt_id}}")
    }
  } else {
    cli::cli_alert_success("Wrote synthetic bundle to {.path {out_path}}")
    cli::cli_alert_info("Receipt ID: {.val {receipts[[1L]]$receipt_id}}")
  }

  cli_status_ok()
}

cli_cmd_generator_revoke <- function(args) {
  opts <- cli_parse_options(args, allowed = c("store", "contract-id", "reason"))
  if (length(opts$positionals) > 0L) {
    cli_usage_error("generator revoke takes no positional arguments")
  }

  store_path <- cli_require_option(opts, "store")
  contract_id <- cli_require_option(opts, "contract-id")
  reason <- cli_require_option(opts, "reason")

  frozen <- generator_api_recover_frozen_handle(store_path, contract_id)

  tryCatch(
    revoke_generator(frozen, reason),
    dataganger_generator_error = function(e) {
      cli::cli_abort(conditionMessage(e))
    }
  )

  cli::cli_alert_success("Contract {.val {contract_id}} has been revoked.")
  cli_status_ok()
}

cli_cmd_generator_status <- function(args) {
  opts <- cli_parse_options(args, allowed = c("store", "contract-id", "out"))
  if (length(opts$positionals) > 0L) {
    cli_usage_error("generator status takes no positional arguments")
  }

  store_path <- cli_require_option(opts, "store")
  private_store <- cli_generator_open_store(store_path)

  contract_id <- opts$options[["contract-id"]]

  if (!is.null(contract_id)) {
    approval <- cli_generator_read_approval(private_store, contract_id)
    if (is.null(approval)) {
       info <- list(contract_id = contract_id, status = "none")
    } else {
       info <- list(
         contract_id = contract_id,
         status = approval$status,
         revoked_at = approval$revoked_at,
         superseded_by = approval$superseded_by,
         reason = approval$reason
       )
    }

    if (!is.null(opts$options$out)) {
      cli_write_json(info, opts$options$out)
    }

    cli::cli_h1("Generator Status")
    cli::cli_alert_info("Contract ID: {.val {info$contract_id}}")
    cli::cli_alert_info("Status: {.val {info$status}}")

  } else {
    contracts_dir <- file.path(private_store$root, "contracts")
    files <- list.files(contracts_dir, pattern = "^[0-9a-f]{64}\\.json$")
    ids <- sub("\\.json$", "", files)

    statuses <- lapply(ids, function(id) {
      approval <- cli_generator_read_approval(private_store, id)
      list(
        contract_id = id,
        status = if (is.null(approval)) "none" else approval$status
      )
    })

    if (!is.null(opts$options$out)) {
      cli_write_json(statuses, opts$options$out)
    }

    cli::cli_h1("Store Status")
    cli::cli_alert_info("Found {length(statuses)} contract records.")
    for (s in statuses) {
      cli::cli_alert_info("{.val {s$contract_id}}: {s$status}")
    }
  }

  cli_status_ok()
}

#' Write one generation result as the single contract-conforming download
#'
#' Shared by the human operator CLI and the agent broker so both routes emit
#' exactly the same bundle shape. A single dataset yields a standard bundle; a
#' batch yields one zip containing N conforming bundles.
#'
#' @return A list with `receipts` (list of receipts, in dataset order) and
#'   `batch` (logical, whether the result was a multi-dataset batch).
#' @keywords internal
#' @noRd
generator_cli_write_generation <- function(result,
                                           frozen,
                                           approval,
                                           out_path,
                                           acknowledge_kanon = FALSE,
                                           acknowledge_exact_match = FALSE) {
  export_spec <- generator_workspace_export_spec(frozen)
  export_roles <- generator_workspace_export_roles(frozen)

  export_one <- function(synthetic, receipt, output_path) {
    # The generated runtime is source-free, so restore only the reviewed
    # policy metadata needed by the standard export bundle.
    exportable <- synthetic
    attr(exportable, "spec") <- export_spec
    export_synthetic(
      synthetic = exportable,
      path = output_path,
      format = "zip",
      purpose = export_spec$purpose %||% NULL,
      roles = export_roles,
      privacy = cli_generator_export_privacy(synthetic),
      # fail_on_exact_match is deliberately not passed. export_synthetic() only
      # honours it when `original` is supplied, and this path is source-free by
      # design, so the argument would be inert. Exact-row matches are blocked
      # upstream by the runtime privacy check in generate_synthetic(), which has
      # the fitted state and the keyed index this layer does not.
      kanon_acknowledged = isTRUE(acknowledge_kanon),
      exact_match_acknowledged = isTRUE(acknowledge_exact_match),
      generator_provenance = list(
        contract_id = receipt$contract_id %||% frozen$contract_id,
        approval_id = receipt$approval_id %||% approval$approval_id %||% NULL,
        generator_id = receipt$generator_id %||% frozen$generator_id %||% NULL,
        generator_revision = receipt$generator_revision %||%
          frozen$generator_revision %||% NULL,
        request_receipt_id = receipt$request_receipt_id %||% NULL,
        output_receipt_id = receipt$receipt_id %||% NULL
      ),
      overwrite = TRUE
    )
  }

  if (!inherits(result, "dataganger_batch")) {
    receipt <- generation_receipt(result)
    export_one(result, receipt, out_path)
    return(list(receipts = list(receipt), batch = FALSE))
  }

  receipts <- generation_receipt(result)
  parent <- dirname(out_path)
  if (!dir.exists(parent)) {
    cli::cli_abort("Parent directory does not exist: {.file {parent}}")
  }
  staging <- tempfile("dataganger-generator-batch-", tmpdir = parent)
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)

  for (i in seq_along(unclass(result)$datasets)) {
    dataset_dir <- file.path(staging, sprintf("dataset_%02d", i))
    dir.create(dataset_dir, recursive = TRUE, showWarnings = FALSE)
    dataset_zip <- tempfile(
      sprintf("dataganger-generator-dataset-%02d-", i),
      fileext = ".zip"
    )
    export_one(unclass(result)$datasets[[i]], receipts[[i]], dataset_zip)
    utils::unzip(dataset_zip, exdir = dataset_dir)
    unlink(dataset_zip, force = TRUE)
  }

  files <- list.files(staging, recursive = TRUE, all.files = FALSE,
    no.. = TRUE, full.names = TRUE)
  files <- files[!file.info(files)$isdir]
  root <- normalizePath(staging, winslash = "/", mustWork = TRUE)
  relative_files <- sub(
    paste0("^", root, "/?"), "",
    normalizePath(files, winslash = "/", mustWork = TRUE)
  )
  aggregate_zip <- tempfile("dataganger-generator-batch-", tmpdir = parent,
    fileext = ".zip")
  zip::zip(
    zipfile = aggregate_zip,
    files = relative_files,
    root = root
  )
  if (file.exists(out_path)) {
    unlink(out_path, force = TRUE)
  }
  if (!file.rename(aggregate_zip, out_path)) {
    unlink(aggregate_zip, force = TRUE)
    cli::cli_abort("Could not write generator batch bundle to {.path {out_path}}")
  }

  list(receipts = receipts, batch = TRUE)
}
