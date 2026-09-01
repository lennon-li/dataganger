cli_generator_approved_fixture <- function(tmp, data = data.frame(
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

  expect_equal(dataganger_cli(c(
    "generator", "freeze", data_file,
    "--spec", spec_file,
    "--store", file.path(tmp, "store"),
    "--max-datasets", "4",
    "--out", summary_file
  )), 0L)

  summary_data <- jsonlite::fromJSON(summary_file)
  private_store <- generator_api_store(file.path(tmp, "store"))
  contract <- generator_store_read_contract(private_store, summary_data$contract_id)
  generator_store_approve(
    private_store, contract, summary_data$generator_id, "test_user"
  )
  list(
    store = file.path(tmp, "store"),
    contract_id = summary_data$contract_id
  )
}

cli_generator_bundle_csv_bytes <- function(zip_path, member = "synthetic_data.csv") {
  extracted <- withr::local_tempdir()
  utils::unzip(zip_path, files = member, exdir = extracted)
  csv_path <- file.path(extracted, member)
  readBin(csv_path, what = "raw", n = file.info(csv_path)$size)
}

test_that("generator lifecycle commands round-trip against a temporary store", {
  skip_if_not_installed("withr")
  store <- withr::local_tempdir()

  data_file <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(data.frame(a = 1:10, b = 11:20, c = letters[1:10]), data_file)

  spec_file <- withr::local_tempfile(fileext = ".yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)

  out_json <- withr::local_tempfile(fileext = ".json")

  status <- dataganger_cli(c(
    "generator", "freeze",
    data_file,
    "--spec", spec_file,
    "--store", store,
    "--out", out_json
  ))
  expect_equal(status, 0L)

  summary_data <- jsonlite::fromJSON(out_json)
  contract_id <- summary_data$contract_id
  expect_true(is.character(contract_id))

  # Before approval, inspect might fail if we enforce approval (or if it doesn't)
  # BUT we can just approve it in R!
  private_store <- generator_api_store(store)
  record <- generator_store_read_generator_record(private_store, summary_data$generator_id)
  contract <- generator_store_read_contract(private_store, contract_id)
  # approve it manually since there's no CLI command for it
  generator_store_approve(private_store, contract, summary_data$generator_id, "test_user")

  # Now inspect
  inspect_out <- withr::local_tempfile(fileext = ".json")
  status <- dataganger_cli(c(
    "generator", "inspect",
    "--store", store,
    "--contract-id", contract_id,
    "--out", inspect_out
  ))
  expect_equal(status, 0L)

  # Generate
  gen_out <- withr::local_tempfile(fileext = ".zip")
  status <- dataganger_cli(c(
    "generator", "generate",
    "--store", store,
    "--contract-id", contract_id,
    "--out", gen_out,
    "--seed", "123"
  ))
  expect_equal(status, 0L)
  expect_true(file.exists(gen_out))

  # Revoke
  status <- dataganger_cli(c(
    "generator", "revoke",
    "--store", store,
    "--contract-id", contract_id,
    "--reason", "testing"
  ))
  expect_equal(status, 0L)

  # Generate after revoke fails
  status <- dataganger_cli(c(
    "generator", "generate",
    "--store", store,
    "--contract-id", contract_id,
    "--out", gen_out,
    "--seed", "123"
  ))
  expect_equal(status, 1L)

  # Status
  status_out <- withr::local_tempfile(fileext = ".json")
  status <- dataganger_cli(c(
    "generator", "status",
    "--store", store,
    "--out", status_out
  ))
  expect_equal(status, 0L)
})

test_that("out-of-bounds limits fail in generate", {
  skip_if_not_installed("withr")
  store <- withr::local_tempdir()
  data_file <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(data.frame(a = 1:10, b = 11:20, c = letters[1:10]), data_file)
  spec_file <- withr::local_tempfile(fileext = ".yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  out_json <- withr::local_tempfile(fileext = ".json")

  # freeze with max-n 5
  dataganger_cli(c(
    "generator", "freeze", data_file, "--spec", spec_file,
    "--store", store, "--out", out_json, "--max-n", "5"
  ))
  summary_data <- jsonlite::fromJSON(out_json)
  contract_id <- summary_data$contract_id

  private_store <- generator_api_store(store)
  record <- generator_store_read_generator_record(private_store, summary_data$generator_id)
  contract <- generator_store_read_contract(private_store, contract_id)
  generator_store_approve(private_store, contract, summary_data$generator_id, "test_user")

  gen_out <- withr::local_tempfile(fileext = ".csv")
  status <- dataganger_cli(c(
    "generator", "generate",
    "--store", store,
    "--contract-id", contract_id,
    "--out", gen_out,
    "--n", "10"
  ))
  expect_equal(status, 1L)
})

test_that("missing or malformed contract-id fails without leaking store internals", {
  skip_if_not_installed("withr")
  store <- withr::local_tempdir()
  # initialize store
  generator_api_store(store)

  status <- dataganger_cli(c(
    "generator", "inspect",
    "--store", store,
    "--contract-id", "not-a-hash"
  ))
  expect_equal(status, 1L)
})

test_that("path-traversal-shaped contract-id is rejected", {
  skip_if_not_installed("withr")
  store <- withr::local_tempdir()
  generator_api_store(store)

  status <- dataganger_cli(c(
    "generator", "inspect",
    "--store", store,
    "--contract-id", "../../../foo"
  ))
  expect_equal(status, 1L)
})

test_that("missing store is usage error", {
  status <- dataganger_cli(c(
    "generator", "inspect",
    "--contract-id", "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  ))
  expect_equal(status, 2L)
})

test_that("deterministic output works", {
  skip_if_not_installed("withr")
  store <- withr::local_tempdir()
  data_file <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(data.frame(a = 1:10, b = 11:20, c = letters[1:10]), data_file)
  spec_file <- withr::local_tempfile(fileext = ".yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  out_json <- withr::local_tempfile(fileext = ".json")

  dataganger_cli(c(
    "generator", "freeze", data_file, "--spec", spec_file,
    "--store", store, "--out", out_json
  ))
  summary_data <- jsonlite::fromJSON(out_json)
  contract_id <- summary_data$contract_id

  private_store <- generator_api_store(store)
  record <- generator_store_read_generator_record(private_store, summary_data$generator_id)
  contract <- generator_store_read_contract(private_store, contract_id)
  generator_store_approve(private_store, contract, summary_data$generator_id, "test_user")

  out1 <- withr::local_tempfile(fileext = ".zip")
  out2 <- withr::local_tempfile(fileext = ".zip")

  dataganger_cli(c(
    "generator", "generate", "--store", store, "--contract-id", contract_id,
    "--out", out1, "--seed", "123"
  ))
  dataganger_cli(c(
    "generator", "generate", "--store", store, "--contract-id", contract_id,
    "--out", out2, "--seed", "123"
  ))

  expect_identical(
    cli_generator_bundle_csv_bytes(out1),
    cli_generator_bundle_csv_bytes(out2)
  )
})

test_that("freeze accepts a roles YAML file", {
  skip_if_not_installed("withr")
  store <- tempfile("dataganger-cli-roles-store-")
  data_file <- tempfile("dataganger-cli-roles-data-", fileext = ".csv")
  data <- data.frame(
    amount = 1:10,
    group = rep(c("north", "south"), 5),
    stringsAsFactors = FALSE
  )
  readr::write_csv(data, data_file)
  roles_file <- tempfile("dataganger-cli-roles-", fileext = ".yaml")
  cli_write_yaml(roles_to_yaml_list(detect_roles(data)), roles_file)
  spec_file <- tempfile("dataganger-cli-roles-spec-", fileext = ".yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  out_json <- tempfile("dataganger-cli-roles-summary-", fileext = ".json")

  status <- dataganger_cli(c(
    "generator", "freeze", data_file,
    "--spec", spec_file,
    "--roles", roles_file,
    "--store", store,
    "--out", out_json
  ))

  expect_equal(status, 0L)
  expect_true(file.exists(out_json))
  expect_true(dir.exists(store))
})

test_that("read-only generator commands do not create a missing store", {
  skip_if_not_installed("withr")
  store <- tempfile("dataganger-cli-missing-store-")
  contract_id <- strrep("a", 64L)
  commands <- list(
    c("generator", "inspect", "--store", store, "--contract-id", contract_id),
    c("generator", "status", "--store", store),
    c("generator", "generate", "--store", store, "--contract-id", contract_id,
      "--out", tempfile(fileext = ".csv")),
    c("generator", "revoke", "--store", store, "--contract-id", contract_id,
      "--reason", "testing")
  )

  expect_false(dir.exists(store))
  for (command in commands) {
    expect_equal(dataganger_cli(command), 1L)
    expect_false(dir.exists(store))
  }
})

test_that("status lists frozen contracts without approval records", {
  skip_if_not_installed("withr")
  store <- tempfile("dataganger-cli-status-store-")
  data_file <- tempfile("dataganger-cli-status-data-", fileext = ".csv")
  readr::write_csv(
    data.frame(a = 1:10, b = 11:20, c = letters[1:10]),
    data_file
  )
  spec_file <- tempfile("dataganger-cli-status-spec-", fileext = ".yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  freeze_out <- tempfile("dataganger-cli-status-freeze-", fileext = ".json")
  dataganger_cli(c(
    "generator", "freeze", data_file, "--spec", spec_file,
    "--store", store, "--out", freeze_out
  ))
  summary_data <- jsonlite::fromJSON(freeze_out)
  contract_id <- summary_data$contract_id

  status_out <- tempfile("dataganger-cli-status-", fileext = ".json")
  status <- dataganger_cli(c(
    "generator", "status", "--store", store, "--out", status_out
  ))

  expect_equal(status, 0L)
  expect_match(paste(readLines(status_out, warn = FALSE), collapse = " "),
    contract_id, fixed = TRUE)
  expect_match(paste(readLines(status_out, warn = FALSE), collapse = " "),
    "none", fixed = TRUE)
})

test_that("a never-approved contract recovers a valid handle but cannot be revoked", {
  skip_if_not_installed("withr")
  store <- tempfile("dataganger-cli-revoke-store-")
  data_file <- tempfile("dataganger-cli-revoke-data-", fileext = ".csv")
  readr::write_csv(
    data.frame(a = 1:10, b = 11:20, c = letters[1:10]),
    data_file
  )
  spec_file <- tempfile("dataganger-cli-revoke-spec-", fileext = ".yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  freeze_out <- tempfile("dataganger-cli-revoke-freeze-", fileext = ".json")
  dataganger_cli(c(
    "generator", "freeze", data_file, "--spec", spec_file,
    "--store", store, "--out", freeze_out
  ))
  summary_data <- jsonlite::fromJSON(freeze_out)
  contract_id <- summary_data$contract_id

  recovered <- generator_api_recover_frozen_handle(store, contract_id)
  expect_silent(generator_api_validate_frozen(recovered))

  # Revocation is terminal for an existing approval. A contract that was never
  # approved has nothing to revoke, and revoke_generator() must not fabricate an
  # approval record to represent one. Discarding an unapproved contract is a
  # separate, undesigned operation.
  status <- dataganger_cli(c(
    "generator", "revoke", "--store", store,
    "--contract-id", contract_id, "--reason", "testing"
  ))
  expect_equal(status, 1L)
  expect_false(file.exists(
    generator_store_approval_path(generator_store_open(store), contract_id)
  ))
})

test_that("generator generate writes one contract-conforming bundle and provenance", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- cli_generator_approved_fixture(tmp)
  out <- file.path(tmp, "bundle.zip")

  result <- run_cli(c(
    "generator", "generate", "--store", fixture$store,
    "--contract-id", fixture$contract_id, "--out", out,
    "--seed", "123", "--n", "10"
  ))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out))
  listing <- utils::unzip(out, list = TRUE)$Name
  expect_true("synthetic_data.csv" %in% listing)
  expect_true(any(startsWith(listing, "human/")))
  expect_true("agent/manifest.json" %in% listing)

  extracted <- withr::local_tempdir()
  utils::unzip(out, exdir = extracted)
  manifest <- jsonlite::read_json(
    file.path(extracted, "agent", "manifest.json"),
    simplifyVector = FALSE
  )
  expect_identical(manifest$generator_provenance$contract_id, fixture$contract_id)
})

test_that("multiple generator datasets are one archive of separate bundles", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- cli_generator_approved_fixture(tmp)
  out <- file.path(tmp, "batch.zip")

  result <- run_cli(c(
    "generator", "generate", "--store", fixture$store,
    "--contract-id", fixture$contract_id, "--out", out,
    "--seed", "123", "--n", "10", "--datasets", "3"
  ))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out))
  expect_length(list.files(tmp, pattern = "\\.zip$"), 1L)
  listing <- utils::unzip(out, list = TRUE)$Name
  roots <- unique(sub("/.*$", "", listing))
  expect_setequal(roots, sprintf("dataset_%02d", 1:3))
  for (root in roots) {
    expect_true(paste0(root, "/synthetic_data.csv") %in% listing)
    expect_true(any(startsWith(listing, paste0(root, "/human/"))))
    expect_true(paste0(root, "/agent/manifest.json") %in% listing)
  }
})

test_that("generator generate keeps the exact-match export gate strict by default", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- cli_generator_approved_fixture(tmp, data.frame(
    a = rep(1L, 10),
    b = rep("x", 10),
    stringsAsFactors = FALSE
  ))
  out <- file.path(tmp, "blocked.zip")

  result <- run_cli(c(
    "generator", "generate", "--store", fixture$store,
    "--contract-id", fixture$contract_id, "--out", out,
    "--seed", "1", "--n", "10"
  ))

  expect_identical(result$code, 1L)
  expect_false(file.exists(out))
  expect_match(
    paste(c(result$output, result$messages), collapse = " "),
    "exact_row_match|exact-row",
    perl = TRUE
  )
})
