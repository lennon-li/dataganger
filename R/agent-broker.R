# Broker half of the two-process agent boundary (FG-7b).
#
# Runs as the store-owning account. This is the only code on the agent route
# that opens the private store. It answers exactly two operations and accepts
# no store path, no real-data path, and no privacy acknowledgement from the
# caller: freeze, approve, revoke, status, inspect, and migration are
# unreachable here.

#' Fields accepted for each broker operation
#'
#' A strict allowlist. Any other field is rejected rather than ignored, which
#' is what keeps a store path, a real-data path, or a privacy opt-out from
#' reaching the broker from the agent route.
#'
#' @keywords internal
#' @noRd
agent_broker_request_fields <- function(op) {
  switch(
    op,
    capabilities = c("protocol", "op", "contract_id"),
    generate = c("protocol", "op", "contract_id", "n", "datasets", "seed"),
    NULL
  )
}

cli_cmd_generator_broker <- function(args, input = NULL) {
  opts <- cli_parse_options(args, allowed = c("store"))
  if (length(opts$positionals) > 0L) {
    cli_usage_error("generator-broker takes no positional arguments")
  }

  store_root <- opts$options$store
  if (is.null(store_root) || !nzchar(store_root)) {
    store_root <- Sys.getenv("DATAGANGER_BROKER_STORE", "")
  }

  if (is.null(input)) {
    input <- agent_broker_read_stdin()
  }

  response <- NULL
  # The response is the only thing allowed on stdout, so any incidental
  # progress output from the synthesis stack is captured and dropped.
  invisible(utils::capture.output(
    response <- tryCatch(
      agent_broker_handle(input, store_root),
      error = function(e) {
        list(
          ok = FALSE,
          protocol = agent_protocol_version(),
          error = agent_broker_redact(conditionMessage(e), store_root)
        )
      }
    )
  ))

  cat(agent_to_json(response), "\n", sep = "")
  if (isTRUE(response$ok)) cli_status_ok() else cli_status_error()
}

agent_broker_read_stdin <- function() {
  con <- file("stdin", open = "r")
  on.exit(close(con), add = TRUE)
  paste(readLines(con, warn = FALSE), collapse = "\n")
}

#' Keep the store path out of error text returned to the agent
#'
#' @keywords internal
#' @noRd
agent_broker_redact <- function(message, store_root) {
  if (!is.character(message) || length(message) != 1L) {
    return("The broker refused the request.")
  }
  roots <- unique(c(
    store_root,
    tryCatch(normalizePath(store_root, mustWork = FALSE), error = function(e) NULL)
  ))
  for (root in roots) {
    if (is.character(root) && length(root) == 1L && nzchar(root)) {
      message <- gsub(root, "<store>", message, fixed = TRUE)
    }
  }
  message
}

agent_broker_handle <- function(input, store_root) {
  if (!is.character(store_root) || length(store_root) != 1L || !nzchar(store_root)) {
    agent_abort("Broker store is not configured. Set --store or DATAGANGER_BROKER_STORE.")
  }

  request <- tryCatch(
    agent_from_json(input),
    error = function(e) agent_abort("Malformed broker request.")
  )
  if (!is.list(request) || is.null(names(request)) || any(!nzchar(names(request)))) {
    agent_abort("Malformed broker request.")
  }
  if (!identical(request$protocol, agent_protocol_version())) {
    agent_abort(sprintf(
      "Unsupported protocol. This broker speaks %s.", agent_protocol_version()
    ))
  }

  op <- request$op
  if (!is.character(op) || length(op) != 1L || !nzchar(op)) {
    agent_abort("Broker request is missing an operation.")
  }
  allowed <- agent_broker_request_fields(op)
  if (is.null(allowed)) {
    agent_abort(sprintf(
      "Operation %s is not available on the agent route.", op
    ))
  }
  unknown <- setdiff(names(request), allowed)
  if (length(unknown) > 0L) {
    agent_abort(sprintf(
      "Rejected request fields not allowed on the agent route: %s.",
      paste(sort(unknown), collapse = ", ")
    ))
  }

  root <- normalizePath(store_root, mustWork = FALSE)
  if (!file.exists(generator_store_marker_path(root))) {
    agent_abort("The configured broker store is not a DataGangeR private store.")
  }

  contract_id <- request$contract_id
  if (!is.character(contract_id) || length(contract_id) != 1L || !nzchar(contract_id)) {
    agent_abort("Broker request is missing contract_id.")
  }

  switch(
    op,
    capabilities = agent_broker_capabilities(root, contract_id),
    generate = agent_broker_generate(root, contract_id, request)
  )
}

agent_broker_approval <- function(store, contract_id) {
  path <- generator_store_approval_path(store, contract_id)
  if (!file.exists(path)) {
    return(NULL)
  }
  generator_store_read_approval(store, contract_id)
}

agent_broker_capabilities <- function(root, contract_id) {
  principal <- agent_principal()
  if (is.null(principal)) {
    agent_abort("The broker could not determine its own OS principal.")
  }

  store <- generator_store_open(root)
  contract <- tryCatch(
    generator_store_read_contract(store, contract_id),
    error = function(e) agent_abort("Contract not found in the broker store.")
  )
  approval <- agent_broker_approval(store, contract_id)

  list(
    ok = TRUE,
    protocol = agent_protocol_version(),
    op = "capabilities",
    principal = principal,
    # Reported so the client can attempt a real read against a path whose
    # existence has been established remotely. A local read failure is then a
    # refusal, with no need to classify OS error text.
    store_root = root,
    contract = list(
      contract_id = contract$contract_id,
      contract_version = contract$contract_version,
      schema_version = contract$schema_version,
      limits = unclass(contract$allowed),
      approval_status = if (is.null(approval)) "none" else approval$status
    )
  )
}

agent_broker_request_int <- function(value, name) {
  if (is.null(value)) {
    return(NULL)
  }
  if (length(value) != 1L || !is.numeric(value) || is.na(value) ||
    value != trunc(value)) {
    agent_abort(sprintf("Request field %s must be a single whole number.", name))
  }
  as.integer(value)
}

agent_broker_generate <- function(root, contract_id, request) {
  n <- agent_broker_request_int(request$n, "n")
  seed <- agent_broker_request_int(request$seed, "seed")
  datasets <- agent_broker_request_int(request$datasets, "datasets")
  if (is.null(datasets)) {
    datasets <- 1L
  }

  store <- generator_store_open(root)
  approval <- agent_broker_approval(store, contract_id)
  if (is.null(approval) || !identical(approval$status, "approved")) {
    agent_abort(
      "This contract has no active approval, so the agent route cannot generate."
    )
  }

  frozen <- generator_api_recover_frozen_handle(root, contract_id)
  result <- tryCatch(
    generate_synthetic(frozen, seed = seed, n = n, datasets = datasets),
    dataganger_generator_error = function(e) agent_abort(conditionMessage(e))
  )

  out_path <- tempfile("dataganger-agent-bundle-", fileext = ".zip")
  on.exit(unlink(out_path, force = TRUE), add = TRUE)

  written <- generator_cli_write_generation(
    result = result,
    frozen = frozen,
    approval = approval,
    out_path = out_path,
    # The agent route carries strict privacy defaults and has no way to
    # acknowledge or opt out of them.
    acknowledge_kanon = FALSE,
    acknowledge_exact_match = FALSE
  )

  size <- file.size(out_path)
  if (is.na(size) || size <= 0) {
    agent_abort("The broker produced no bundle.")
  }
  if (size > agent_max_bundle_bytes()) {
    agent_abort(sprintf(
      "Bundle of %d bytes exceeds the %d byte agent transfer limit.",
      size, agent_max_bundle_bytes()
    ))
  }

  list(
    ok = TRUE,
    protocol = agent_protocol_version(),
    op = "generate",
    batch = isTRUE(written$batch),
    receipts = lapply(written$receipts, agent_broker_public_receipt),
    bundle_base64 = jsonlite::base64_enc(readBin(out_path, "raw", n = size))
  )
}

#' Reduce a receipt to provenance identifiers
#'
#' The agent receives identifiers it can quote back, never fitted state or
#' anything derived from the source data.
#'
#' @keywords internal
#' @noRd
agent_broker_public_receipt <- function(receipt) {
  keep <- c(
    "receipt_id", "request_receipt_id", "contract_id", "approval_id",
    "generator_id", "generator_revision"
  )
  values <- lapply(keep, function(field) receipt[[field]])
  names(values) <- keep
  values[!vapply(values, is.null, logical(1L))]
}
