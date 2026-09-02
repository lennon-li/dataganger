# FG-7b: the two-process agent boundary.
#
# Read this before adding tests here. A previous FG-7b attempt was discarded
# because its tests asserted a boundary that did not exist: they locked one
# marker file with chmod 000, left the fitted state readable, and passed. The
# rules that keep these tests honest:
#
#   * Never fabricate a store, a marker, or a symlink farm for the client to
#     probe. The client probes the real store the broker reports.
#   * A test that claims a read was refused must first assert that the read
#     really was refused, on the real path, in that process.
#   * `available = TRUE` is unreachable on a single-account host, because the
#     broker and the client are then the same principal. Do not engineer it.
#     The end-to-end generate test is gated on a host that supplies two
#     accounts.

agent_test_fixture <- function(tmp, data = data.frame(
  a = 1:10,
  b = 11:20,
  c = letters[1:10],
  stringsAsFactors = FALSE
)) {
  data_file <- file.path(tmp, "data.csv")
  readr::write_csv(data, data_file)
  spec_file <- file.path(tmp, "spec.yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  summary_file <- file.path(tmp, "summary.json")
  store <- file.path(tmp, "store")

  expect_equal(dataganger_cli(c(
    "generator", "freeze", data_file,
    "--spec", spec_file,
    "--store", store,
    "--max-datasets", "4",
    "--out", summary_file
  )), 0L)

  summary_data <- jsonlite::fromJSON(summary_file)
  list(
    store = store,
    contract_id = summary_data$contract_id,
    generator_id = summary_data$generator_id
  )
}

agent_test_approve <- function(fixture) {
  private_store <- generator_api_store(fixture$store)
  contract <- generator_store_read_contract(private_store, fixture$contract_id)
  generator_store_approve(
    private_store, contract, fixture$generator_id, "test_user"
  )
  invisible(fixture)
}

agent_test_request <- function(op, ...) {
  as.character(agent_to_json(c(
    list(protocol = agent_protocol_version(), op = op), list(...)
  )))
}

# Runs the broker in-process and returns its parsed JSON response, exactly as
# the client would parse it off stdout.
agent_test_broker <- function(store, request_json) {
  output <- utils::capture.output(
    status <- cli_cmd_generator_broker(c("--store", store), input = request_json)
  )
  parsed <- agent_from_json(paste(output, collapse = "\n"))
  parsed$status <- status
  parsed
}


# Builds a real broker command the client can spawn as a separate process.
# Returns NULL when this environment cannot run one, so callers skip rather
# than silently degrade to an in-process stand-in.
agent_test_broker_command <- function(tmp, store) {
  rscript <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(rscript)) {
    return(NULL)
  }
  root <- normalizePath(file.path(getwd(), "..", ".."), mustWork = FALSE)
  loader <- if (file.exists(file.path(root, "DESCRIPTION"))) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      return(NULL)
    }
    sprintf("suppressMessages(pkgload::load_all(\"%s\", quiet = TRUE))", root)
  } else if (requireNamespace("dataganger", quietly = TRUE)) {
    "suppressMessages(library(dataganger))"
  } else {
    return(NULL)
  }

  script <- file.path(tmp, "broker.sh")
  command <- paste(script, "generator-broker --store", store)
  # The invocation is split on whitespace, so a path containing spaces cannot
  # be expressed. Skip rather than mis-parse it.
  if (grepl("[[:space:]]", script) || grepl("[[:space:]]", store)) {
    return(NULL)
  }

  expr <- paste0(
    loader,
    "; dataganger::dataganger_cli(commandArgs(trailingOnly = TRUE), quit = TRUE)"
  )
  writeLines(
    c("#!/bin/sh", sprintf("exec %s -e %s \"$@\"", shQuote(rscript), shQuote(expr))),
    script
  )
  Sys.chmod(script, "0755")
  command
}


# ---- Broker request surface -------------------------------------------------

test_that("the broker answers a capabilities probe with principal, root, and limits", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  response <- agent_test_broker(
    fixture$store,
    agent_test_request("capabilities", contract_id = fixture$contract_id)
  )

  expect_true(isTRUE(response$ok))
  expect_equal(response$status, 0L)
  expect_equal(response$protocol, agent_protocol_version())
  expect_true(agent_valid_principal(response$principal))
  expect_equal(
    normalizePath(response$store_root),
    normalizePath(fixture$store)
  )
  expect_equal(response$contract$contract_id, fixture$contract_id)
  expect_equal(response$contract$approval_status, "approved")
  expect_equal(response$contract$limits$datasets[[2L]], 4L)
})

test_that("the broker rejects request fields that are not on the agent route", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  # Each of these is a field an agent must never be able to supply.
  smuggled <- list(
    store = "/some/other/store",
    data = "/home/user/real_patients.csv",
    acknowledge_kanon = TRUE,
    acknowledge_exact_match = TRUE,
    fail_on_exact_match = FALSE
  )

  for (field in names(smuggled)) {
    request <- c(
      list(
        protocol = agent_protocol_version(),
        op = "generate",
        contract_id = fixture$contract_id
      ),
      stats::setNames(list(smuggled[[field]]), field)
    )
    response <- agent_test_broker(
      fixture$store, as.character(agent_to_json(request))
    )
    expect_false(isTRUE(response$ok))
    expect_equal(response$status, 1L)
    expect_match(response$error, field, fixed = TRUE)
  }
})

test_that("privileged operations are unreachable from the broker", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  for (op in c("freeze", "approve", "revoke", "destroy", "inspect", "status", "migrate")) {
    response <- agent_test_broker(
      fixture$store,
      agent_test_request(op, contract_id = fixture$contract_id)
    )
    expect_false(isTRUE(response$ok))
    expect_match(response$error, "not available on the agent route")
  }
})

test_that("the broker refuses malformed, mis-versioned, and store-less requests", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  malformed <- agent_test_broker(fixture$store, "{not json")
  expect_false(isTRUE(malformed$ok))
  expect_match(malformed$error, "Malformed")

  wrong_version <- agent_test_broker(fixture$store, as.character(agent_to_json(list(
    protocol = "DGF-AGENT-V0",
    op = "capabilities",
    contract_id = fixture$contract_id
  ))))
  expect_false(isTRUE(wrong_version$ok))
  expect_match(wrong_version$error, "Unsupported protocol")

  no_store <- withr::with_envvar(
    c(DATAGANGER_BROKER_STORE = ""),
    {
      output <- utils::capture.output(
        status <- cli_cmd_generator_broker(
          character(),
          input = agent_test_request(
            "capabilities", contract_id = fixture$contract_id
          )
        )
      )
      expect_equal(status, 1L)
      agent_from_json(paste(output, collapse = "\n"))
    }
  )
  expect_false(isTRUE(no_store$ok))
  expect_match(no_store$error, "not configured")
})

test_that("the broker refuses to generate without an active approval", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_fixture(tmp)

  response <- agent_test_broker(
    fixture$store,
    agent_test_request("generate", contract_id = fixture$contract_id, n = 5L)
  )

  expect_false(isTRUE(response$ok))
  expect_match(response$error, "no active approval")
})

test_that("the broker returns a contract-conforming bundle and public receipts only", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  response <- agent_test_broker(
    fixture$store,
    agent_test_request(
      "generate", contract_id = fixture$contract_id, n = 8L, seed = 42L
    )
  )

  expect_true(isTRUE(response$ok))
  expect_false(isTRUE(response$batch))

  bundle <- file.path(tmp, "bundle.zip")
  writeBin(jsonlite::base64_dec(response$bundle_base64), bundle)
  members <- utils::unzip(bundle, list = TRUE)$Name
  expect_contains(members, c(
    "synthetic_data.csv",
    "human/human.md",
    "agent/recipe.yaml",
    "agent/manifest.json",
    "agent/AGENT.md"
  ))

  receipt <- response$receipts[[1L]]
  expect_equal(receipt$contract_id, fixture$contract_id)
  expect_true(nzchar(receipt$receipt_id))
  # Name the unexpected fields rather than asserting an opaque aggregate, so a
  # regression that leaks fitted state says which field leaked.
  expect_equal(
    setdiff(names(receipt), c(
      "receipt_id", "request_receipt_id", "contract_id", "approval_id",
      "generator_id", "generator_revision"
    )),
    character()
  )
})

test_that("a multi-dataset request returns one zip of conforming bundles", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  response <- agent_test_broker(
    fixture$store,
    agent_test_request(
      "generate", contract_id = fixture$contract_id, n = 8L, datasets = 3L
    )
  )

  expect_true(isTRUE(response$ok))
  expect_true(isTRUE(response$batch))
  expect_length(response$receipts, 3L)

  bundle <- file.path(tmp, "batch.zip")
  writeBin(jsonlite::base64_dec(response$bundle_base64), bundle)
  members <- utils::unzip(bundle, list = TRUE)$Name
  expect_contains(members, c(
    "dataset_01/synthetic_data.csv",
    "dataset_02/synthetic_data.csv",
    "dataset_03/synthetic_data.csv"
  ))
})

test_that("broker error text does not disclose the private store path", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  response <- agent_test_broker(
    fixture$store,
    agent_test_request("capabilities", contract_id = strrep("0", 64L))
  )

  expect_false(isTRUE(response$ok))
  expect_false(grepl(fixture$store, response$error, fixed = TRUE))
  expect_false(grepl(
    normalizePath(fixture$store), response$error,
    fixed = TRUE
  ))
})


# ---- Store read probe -------------------------------------------------------

test_that("agent_store_readable() reports a readable store as readable", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  expect_true(agent_store_readable(fixture$store))
})

test_that("agent_store_readable() reports a genuinely refused store as refused", {
  skip_on_os("windows")
  skip_if_not_installed("withr")
  skip_if(identical(agent_principal()$id, "0"), "root bypasses permission bits")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  # Lock the whole store root, not one marker inside it. The discarded FG-7b
  # attempt locked only the marker and left the fitted state readable.
  Sys.chmod(fixture$store, "0000")
  withr::defer(Sys.chmod(fixture$store, "0700"))

  # Prove the refusal is real before asserting anything about it.
  expect_error(readLines(
    generator_store_marker_path(fixture$store),
    n = 1L, warn = FALSE
  ))
  expect_error(readLines(
    file.path(fixture$store, "generators", paste0(fixture$generator_id, ".json")),
    n = 1L, warn = FALSE
  ))

  expect_false(agent_store_readable(fixture$store))
})


# ---- Handshake --------------------------------------------------------------

test_that("the handshake is unavailable when no broker is configured", {
  result <- agent_handshake(strrep("a", 64L), broker = "")
  expect_false(result$available)
  expect_match(result$reason, "DATAGANGER_AGENT_BROKER")
})

test_that("the handshake is unavailable when the client cannot identify itself", {
  testthat::local_mocked_bindings(agent_principal = function() NULL)
  result <- agent_handshake(strrep("a", 64L), broker = "/bin/true")
  expect_false(result$available)
  expect_match(result$reason, "own OS principal")
})

test_that("the handshake is unavailable when the client is a superuser", {
  testthat::local_mocked_bindings(
    agent_principal = function() list(scheme = "posix-uid", id = "0")
  )
  result <- agent_handshake(strrep("a", 64L), broker = "/bin/true")
  expect_false(result$available)
  expect_match(result$reason, "superuser")
})

test_that("the handshake is unavailable when the broker is unreachable or mute", {
  skip_on_os("windows")
  result <- agent_handshake(strrep("a", 64L), broker = "/bin/true")
  expect_false(result$available)
  expect_match(result$reason, "did not return a readable response")
})

test_that("a same-principal broker is refused, because that is policy and not a boundary", {
  skip_on_os("windows")
  skip_if_not_installed("withr")
  skip_if(is.null(agent_principal()), "cannot determine the test principal")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  broker <- agent_test_broker_command(tmp, fixture$store)
  skip_if(is.null(broker), "no runnable broker command in this environment")

  result <- agent_handshake(fixture$contract_id, broker = broker)
  expect_false(result$available)
  expect_match(result$reason, "same OS principal")
})

test_that("a readable store is refused even when the principals differ", {
  # This is the exact failure the discarded FG-7b attempt shipped: two
  # principals, but fitted state the client could still read.
  skip_on_os("windows")
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  broker <- agent_test_broker_command(tmp, fixture$store)
  skip_if(is.null(broker), "no runnable broker command in this environment")

  # Only the client's reported identity is substituted, so the broker really
  # answers and the store really is read. The store stays readable.
  testthat::local_mocked_bindings(
    agent_principal = function() {
      list(scheme = "posix-uid", id = "424242")
    }
  )
  expect_true(agent_store_readable(fixture$store))

  result <- agent_handshake(fixture$contract_id, broker = broker)
  expect_false(result$available)
  expect_match(result$reason, "no isolation boundary exists")
})

test_that("a single-account host can never report the agent capability available", {
  # Guards the property the design rests on: one account cannot both hold the
  # store open and prove it cannot read it. If this test ever starts failing,
  # something has fabricated a boundary.
  skip_on_os("windows")
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- agent_test_approve(agent_test_fixture(tmp))

  broker <- agent_test_broker_command(tmp, fixture$store)
  skip_if(is.null(broker), "no runnable broker command in this environment")

  result <- agent_handshake(fixture$contract_id, broker = broker)
  expect_false(result$available)
})


# ---- Agent CLI surface ------------------------------------------------------

test_that("privileged subcommands are unreachable from the agent route", {
  for (subcmd in c("freeze", "approve", "revoke", "destroy", "inspect", "status-all", "migrate")) {
    expect_equal(dataganger_cli(c("agent", subcmd)), 2L)
  }
})

test_that("the agent route accepts no store path, data path, or privacy opt-out", {
  contract_id <- strrep("a", 64L)
  rejected <- list(
    c("--store", "/srv/store"),
    c("--data", "/home/user/real.csv"),
    c("--acknowledge-kanon", "true"),
    c("--acknowledge-exact-match", "true")
  )
  for (extra in rejected) {
    expect_equal(
      dataganger_cli(c(
        "agent", "generate", "--contract-id", contract_id,
        "--out", file.path(tempdir(), "out.zip"), extra
      )),
      2L
    )
  }
})

test_that("agent status and generate fail closed with no broker configured", {
  skip_if_not_installed("withr")
  contract_id <- strrep("a", 64L)
  out <- file.path(withr::local_tempdir(), "out.zip")

  withr::with_envvar(c(DATAGANGER_AGENT_BROKER = ""), {
    expect_equal(
      dataganger_cli(c("agent", "status", "--contract-id", contract_id)), 1L
    )
    expect_equal(
      dataganger_cli(c(
        "agent", "generate", "--contract-id", contract_id, "--out", out
      )),
      1L
    )
    expect_false(file.exists(out))
  })
})


test_that("a bundle for a different contract is refused rather than written", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "out.zip")

  # A broker that answers a well-formed handshake but returns provenance for
  # some other contract, as a mis-pointed store would.
  requested <- strrep("a", 64L)
  testthat::local_mocked_bindings(
    agent_handshake = function(contract_id, ...) {
      list(
        available = TRUE,
        argv = "/bin/true",
        principal = list(scheme = "posix-uid", id = "1000"),
        broker_principal = list(scheme = "posix-uid", id = "1001"),
        store_root = "/srv/store",
        contract = list(contract_id = contract_id, approval_status = "approved")
      )
    },
    agent_broker_call = function(argv, request) {
      list(
        ok = TRUE,
        protocol = agent_protocol_version(),
        op = "generate",
        batch = FALSE,
        receipts = list(list(
          receipt_id = "r1", contract_id = strrep("b", 64L)
        )),
        bundle_base64 = jsonlite::base64_enc(charToRaw("not the right bundle"))
      )
    }
  )

  expect_equal(
    dataganger_cli(c(
      "agent", "generate", "--contract-id", requested, "--out", out
    )),
    1L
  )
  expect_false(file.exists(out))
})


# ---- End-to-end across two real accounts ------------------------------------

test_that("agent generation succeeds across a real host-supplied boundary", {
  # Gated because the boundary is host-supplied: the package cannot create a
  # second account. Configure DATAGANGER_AGENT_BROKER to the whitelisted
  # invocation, DATAGANGER_AGENT_E2E_CONTRACT to an approved contract in the
  # broker's store, and set DATAGANGER_AGENT_E2E=true. See the reference host
  # configuration in inst/agent-skill/SKILL.md.
  skip_if_not(
    identical(tolower(Sys.getenv("DATAGANGER_AGENT_E2E", "")), "true"),
    "two-account agent boundary not configured on this host"
  )
  skip_if_not_installed("withr")

  contract_id <- Sys.getenv("DATAGANGER_AGENT_E2E_CONTRACT", "")
  expect_true(nzchar(contract_id))

  handshake <- agent_handshake(contract_id)
  expect_true(handshake$available)
  expect_false(identical(handshake$principal$id, handshake$broker_principal$id))
  expect_false(agent_store_readable(handshake$store_root))

  out <- file.path(withr::local_tempdir(), "bundle.zip")
  expect_equal(
    dataganger_cli(c(
      "agent", "generate", "--contract-id", contract_id, "--out", out
    )),
    0L
  )
  expect_true(file.exists(out))
  expect_contains(utils::unzip(out, list = TRUE)$Name, "synthetic_data.csv")
})
