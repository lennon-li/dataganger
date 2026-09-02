# Agent client half of the two-process boundary (FG-7b).
#
# Runs as a principal that has no read access to the private store, and never
# opens the store. It reaches the broker through one host-whitelisted command
# and refuses to generate until it has verified, by real attempted reads, that
# a boundary actually exists. Every check fails closed: any unexpected
# condition is unavailable, never available.

agent_broker_argv <- function(spec = Sys.getenv("DATAGANGER_AGENT_BROKER", "")) {
  if (!is.character(spec) || length(spec) != 1L) {
    return(NULL)
  }
  parts <- strsplit(trimws(spec), "[[:space:]]+")[[1L]]
  parts <- parts[nzchar(parts)]
  if (!length(parts)) {
    return(NULL)
  }
  parts
}

#' Send one request to the broker and parse its single JSON response
#'
#' The broker is invoked directly rather than through a shell, so the
#' configured invocation is never re-parsed by a command interpreter.
#'
#' @keywords internal
#' @noRd
agent_broker_call <- function(argv, request) {
  payload <- as.character(agent_to_json(request))
  out <- suppressWarnings(tryCatch(
    system2(argv[[1L]], args = argv[-1L], input = payload,
      stdout = TRUE, stderr = FALSE),
    error = function(e) NULL,
    warning = function(w) NULL
  ))
  if (is.null(out) || !length(out)) {
    return(NULL)
  }
  text <- paste(out, collapse = "\n")
  parsed <- tryCatch(agent_from_json(text), error = function(e) NULL)
  if (!is.list(parsed)) {
    return(NULL)
  }
  parsed
}

#' Can this process read the private store?
#'
#' Returns `TRUE` when a read succeeded (so no boundary exists), `FALSE` when
#' both reads were refused, and `NA` when access could not be evaluated.
#'
#' The broker has already asserted that the store root exists, so a local
#' failure here is a refusal. That is deliberate: classifying the failure by
#' matching OS error text would be locale-dependent, which is the defect class
#' that produced the 0.8.2 CRAN error.
#'
#' @keywords internal
#' @noRd
agent_store_readable <- function(store_root) {
  marker <- generator_store_marker_path(store_root)
  generators <- file.path(store_root, "generators")

  marker_read <- tryCatch(
    {
      readLines(marker, n = 1L, warn = FALSE)
      TRUE
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )

  dir_read <- tryCatch(
    {
      entries <- list.files(generators, all.files = TRUE, no.. = TRUE)
      if (length(entries) > 0L) {
        TRUE
      } else {
        # An unreadable directory and an empty readable one both list as
        # nothing, so ask the OS directly.
        access <- file.access(generators, mode = 4L)
        if (length(access) != 1L || is.na(access)) NA else identical(as.integer(access), 0L)
      }
    },
    error = function(e) NA,
    warning = function(w) NA
  )

  if (isTRUE(marker_read) || isTRUE(dir_read)) {
    return(TRUE)
  }
  if (is.na(dir_read)) {
    return(NA)
  }
  FALSE
}

#' Verify the isolation boundary before any generation
#'
#' @return A list with `available`. When `FALSE`, `reason` says why. When
#'   `TRUE`, the broker invocation, both principals, the store root, and the
#'   contract's public limits are returned.
#' @keywords internal
#' @noRd
agent_handshake <- function(contract_id,
                            broker = Sys.getenv("DATAGANGER_AGENT_BROKER", "")) {
  unavailable <- function(reason) list(available = FALSE, reason = reason)

  # 1. A broker invocation is configured.
  argv <- agent_broker_argv(broker)
  if (is.null(argv)) {
    return(unavailable(
      "No broker invocation is configured; set DATAGANGER_AGENT_BROKER."
    ))
  }

  client <- agent_principal()
  if (is.null(client)) {
    return(unavailable("The client could not determine its own OS principal."))
  }
  # 4. Root defeats permission bits, so its read refusal would prove nothing.
  if (agent_principal_is_superuser(client)) {
    return(unavailable(
      "The client runs as a superuser, so a refused read would prove nothing."
    ))
  }

  # 2. Capabilities probe.
  response <- agent_broker_call(argv, list(
    protocol = agent_protocol_version(),
    op = "capabilities",
    contract_id = contract_id
  ))
  if (is.null(response)) {
    return(unavailable("The broker did not return a readable response."))
  }
  if (!identical(response$protocol, agent_protocol_version())) {
    return(unavailable("The broker speaks a different protocol version."))
  }
  if (!isTRUE(response$ok)) {
    reason <- response$error
    if (!is.character(reason) || length(reason) != 1L) {
      reason <- "no reason given"
    }
    return(unavailable(paste0("The broker refused the capabilities probe: ", reason)))
  }

  broker_principal <- response$principal
  if (!agent_valid_principal(broker_principal) ||
    !identical(broker_principal$scheme, client$scheme)) {
    return(unavailable("The broker did not report a comparable OS principal."))
  }
  # 3. Same principal means policy-only separation, not a boundary.
  if (identical(broker_principal$id, client$id)) {
    return(unavailable(
      "The broker runs as the same OS principal as the client, which is policy, not a boundary."
    ))
  }

  store_root <- response$store_root
  if (!is.character(store_root) || length(store_root) != 1L || !nzchar(store_root)) {
    return(unavailable("The broker did not report its store root."))
  }

  # 5. Real reads of the private store must both fail.
  readable <- agent_store_readable(store_root)
  if (is.na(readable)) {
    return(unavailable(
      "The client could not evaluate its own access to the private store."
    ))
  }
  if (isTRUE(readable)) {
    return(unavailable(
      "The client can read the private store, so no isolation boundary exists."
    ))
  }

  contract <- response$contract
  if (!is.list(contract) || !identical(contract$contract_id, contract_id)) {
    return(unavailable("The broker returned a different contract."))
  }
  if (!identical(contract$approval_status, "approved")) {
    return(unavailable(sprintf(
      "Contract approval status is %s, so generation is not permitted.",
      contract$approval_status %||% "unknown"
    )))
  }

  list(
    available = TRUE,
    reason = NA_character_,
    argv = argv,
    principal = client,
    broker_principal = broker_principal,
    store_root = store_root,
    contract = contract
  )
}

cli_cmd_agent <- function(args) {
  if (length(args) == 0L || args[[1L]] %in% c("-h", "--help")) {
    cli_print_agent_help()
    return(cli_status_ok())
  }

  subcmd <- args[[1L]]
  rest <- args[-1L]

  switch(
    subcmd,
    status = cli_cmd_agent_status(rest),
    generate = cli_cmd_agent_generate(rest),
    {
      cli::cli_alert_danger("Not available on the agent route: {subcmd}")
      cli::cli_alert_info(
        "The agent route offers only {.code status} and {.code generate}. Freezing, approval, revocation, inspection, and migration are human operator actions."
      )
      cli_status_usage()
    }
  )
}

cli_print_agent_help <- function() {
  cat(
    paste(
      "Usage: dataganger agent <command> [options]",
      "",
      "Commands:",
      "  status --contract-id <id>",
      "  generate --contract-id <id> --out <path> [--seed <int>] [--n <int>] [--datasets <int>]",
      "",
      "The agent route reaches the private store only through the broker named",
      "by DATAGANGER_AGENT_BROKER, and reports itself unavailable unless the",
      "broker runs as a different OS principal whose store this process cannot",
      "read. It accepts no store path, no data path, and no privacy opt-out.",
      sep = "\n"
    ),
    "\n",
    sep = ""
  )
}

cli_cmd_agent_status <- function(args) {
  opts <- cli_parse_options(args, allowed = "contract-id")
  if (length(opts$positionals) > 0L) {
    cli_usage_error("agent status takes no positional arguments")
  }
  contract_id <- cli_require_option(opts, "contract-id")

  handshake <- agent_handshake(contract_id)

  cli::cli_h1("DataGangeR Agent Capability")
  if (!isTRUE(handshake$available)) {
    cli::cli_alert_danger("Status: {.val unavailable}")
    cli::cli_alert_info("{handshake$reason}")
    return(cli_status_error())
  }

  cli::cli_alert_success("Status: {.val available}")
  cli::cli_alert_info("Contract ID: {.val {handshake$contract$contract_id}}")
  limits <- handshake$contract$limits
  cli::cli_alert_info(
    "Allowed rows: {limits$n[[1L]]}-{limits$n[[2L]]}; datasets: {limits$datasets[[1L]]}-{limits$datasets[[2L]]}"
  )
  cli_status_ok()
}

cli_cmd_agent_generate <- function(args) {
  # No --store, no data path, and no acknowledgement flags: cli_parse_options()
  # rejects any option outside this list.
  opts <- cli_parse_options(
    args,
    allowed = c("contract-id", "out", "seed", "n", "datasets")
  )
  if (length(opts$positionals) > 0L) {
    cli_usage_error("agent generate takes no positional arguments")
  }

  contract_id <- cli_require_option(opts, "contract-id")
  out_path <- cli_require_option(opts, "out")

  parent <- dirname(out_path)
  if (!dir.exists(parent)) {
    cli::cli_abort("Parent directory does not exist: {.file {parent}}")
  }

  handshake <- agent_handshake(contract_id)
  if (!isTRUE(handshake$available)) {
    cli::cli_alert_danger("Agent generation is unavailable: {handshake$reason}")
    return(cli_status_error())
  }

  request <- list(
    protocol = agent_protocol_version(),
    op = "generate",
    contract_id = contract_id
  )
  for (field in c("seed", "n", "datasets")) {
    value <- opts$options[[field]]
    if (!is.null(value)) {
      request[[field]] <- cli_agent_parse_int(value, field)
    }
  }

  response <- agent_broker_call(handshake$argv, request)
  if (is.null(response)) {
    cli::cli_alert_danger("The broker did not return a readable response.")
    return(cli_status_error())
  }
  if (!isTRUE(response$ok)) {
    reason <- response$error
    if (!is.character(reason) || length(reason) != 1L) {
      reason <- "no reason given"
    }
    cli::cli_alert_danger("The broker refused the request: {reason}")
    return(cli_status_error())
  }

  # Defence in depth against a mis-pointed broker: the provenance that came
  # back must name the contract that was asked for.
  receipts <- response$receipts
  if (!is.list(receipts) || !length(receipts)) {
    cli::cli_alert_danger("The broker returned no generation receipt.")
    return(cli_status_error())
  }
  mismatched <- vapply(
    receipts,
    function(receipt) !identical(receipt$contract_id, contract_id),
    logical(1L)
  )
  if (any(mismatched)) {
    cli::cli_alert_danger(
      "The broker returned a bundle for a different contract; refusing to write it."
    )
    return(cli_status_error())
  }

  bundle <- response$bundle_base64
  if (!is.character(bundle) || length(bundle) != 1L || !nzchar(bundle)) {
    cli::cli_alert_danger("The broker returned no bundle.")
    return(cli_status_error())
  }
  bytes <- tryCatch(jsonlite::base64_dec(bundle), error = function(e) NULL)
  if (is.null(bytes) || !length(bytes)) {
    cli::cli_alert_danger("The broker returned an unreadable bundle.")
    return(cli_status_error())
  }
  writeBin(bytes, out_path)

  if (isTRUE(response$batch)) {
    cli::cli_alert_success(
      "Wrote {length(receipts)} dataset bundles to {.path {out_path}}"
    )
  } else {
    cli::cli_alert_success("Wrote synthetic bundle to {.path {out_path}}")
  }
  for (receipt in receipts) {
    cli::cli_alert_info("Receipt ID: {.val {receipt$receipt_id}}")
  }

  cli_status_ok()
}

cli_agent_parse_int <- function(value, name) {
  parsed <- suppressWarnings(as.integer(value))
  if (length(parsed) != 1L || is.na(parsed)) {
    stop(cli_usage_error(sprintf("Option --%s must be a whole number", name)))
  }
  parsed
}
