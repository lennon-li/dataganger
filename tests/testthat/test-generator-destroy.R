generator_destroy_approved_fixture <- function(tmp) {
  data_file <- file.path(tmp, "data.csv")
  readr::write_csv(data.frame(
    a = 1:10, b = 11:20, c = letters[1:10], stringsAsFactors = FALSE
  ), data_file)
  spec_file <- file.path(tmp, "spec.yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  summary_file <- file.path(tmp, "summary.json")
  expect_identical(dataganger_cli(c(
    "generator", "freeze", data_file,
    "--spec", spec_file, "--store", file.path(tmp, "store"),
    "--max-datasets", "4", "--out", summary_file
  )), 0L)
  summary_data <- jsonlite::fromJSON(summary_file)
  private_store <- generator_api_store(file.path(tmp, "store"))
  contract <- generator_store_read_contract(private_store, summary_data$contract_id)
  generator_store_approve(
    private_store, contract, summary_data$generator_id, "test_user"
  )
  list(store = file.path(tmp, "store"), contract_id = summary_data$contract_id)
}

test_that("destroy_generator removes fitted state and preserves audit receipts", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- generator_destroy_approved_fixture(tmp)
  private_store <- generator_store_open(fixture$store)
  approval <- generator_store_read_approval(private_store, fixture$contract_id)
  generator <- generator_store_read_generator_record(private_store, approval$generator_id)
  fingerprints <- generator$generator$exact_row_index$fingerprints
  generator_path <- generator_store_object_path(private_store, "generators", approval$generator_id)

  frozen <- generator_api_recover_frozen_handle(fixture$store, fixture$contract_id)
  generated <- generate_synthetic(frozen, seed = 123L, n = 10L)
  receipt_id <- generation_receipt(generated)$receipt_id
  expect_true(file.exists(generator_path), info = "fitted generator exists before destruction")

  # Guard against a vacuous leak check: if the index were ever empty, the
  # fingerprint sweep below would pass while proving nothing.
  expect_gt(length(fingerprints), 0L)

  destroyed <- destroy_generator(fixture$store, fixture$contract_id, "retention policy")
  expect_identical(destroyed$status, "destroyed")

  # Destruction must not erase who approved the generator.
  destroyed_approval <- generator_store_read_approval(private_store, fixture$contract_id)
  expect_identical(destroyed_approval$approver, approval$approver)
  expect_match(destroyed_approval$reason, "retention policy", fixed = TRUE)
  expect_false(file.exists(generator_path), info = "fitted generator file was removed")
  expect_true(file.exists(
    generator_store_object_path(private_store, "receipts", receipt_id)
  ), info = "generation receipt survived destruction")

  files <- list.files(fixture$store, recursive = TRUE, full.names = TRUE)
  files <- files[!file.info(files)$isdir]
  remaining_text <- unlist(lapply(files, readLines, warn = FALSE), use.names = FALSE)
  leaked_fingerprints <- fingerprints[vapply(
    fingerprints,
    function(fingerprint) any(grepl(fingerprint, remaining_text, fixed = TRUE)),
    logical(1L)
  )]
  expect_equal(leaked_fingerprints, character(), info = "destroyed row fingerprints remain absent")

  expect_error(
    generate_synthetic(frozen, seed = 123L, n = 10L),
    "destroyed"
  )
  expect_error(
    generator_api_recover_frozen_handle(fixture$store, fixture$contract_id),
    "destroyed"
  )
  again <- destroy_generator(fixture$store, fixture$contract_id, "repeat request")
  expect_identical(again$status, "destroyed")
})

test_that("generator destroy CLI command round-trips", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  fixture <- generator_destroy_approved_fixture(tmp)

  status <- dataganger_cli(c(
    "generator", "destroy", "--store", fixture$store,
    "--contract-id", fixture$contract_id, "--reason", "operator request"
  ))

  expect_identical(status, 0L)
  private_store <- generator_store_open(fixture$store)
  approval <- generator_store_read_approval(private_store, fixture$contract_id)
  expect_identical(approval$status, "destroyed")
  expect_true(file.exists(
    generator_store_object_path(private_store, "contracts", fixture$contract_id)
  ), info = "contract tombstone survived CLI destruction")
})

test_that("destroying a never-approved contract does not fabricate an approval", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  data_file <- file.path(tmp, "data.csv")
  readr::write_csv(data.frame(
    a = 1:10, b = 11:20, c = letters[1:10], stringsAsFactors = FALSE
  ), data_file)
  spec_file <- file.path(tmp, "spec.yaml")
  cat("purpose: development\nengine: internal\n", file = spec_file)
  summary_file <- file.path(tmp, "summary.json")
  expect_identical(dataganger_cli(c(
    "generator", "freeze", data_file,
    "--spec", spec_file, "--store", file.path(tmp, "store"),
    "--out", summary_file
  )), 0L)
  summary_data <- jsonlite::fromJSON(summary_file)
  store <- file.path(tmp, "store")

  # Never approved: no approval record exists yet.
  private_store <- generator_store_open(store)
  expect_false(file.exists(
    generator_store_approval_path(private_store, summary_data$contract_id)
  ))

  destroyed <- destroy_generator(store, summary_data$contract_id, "never used")
  expect_identical(destroyed$status, "destroyed")

  # The tombstone must not claim an approver or an approval time that never
  # existed. revoke_generator() refuses to fabricate an approval record; a
  # destruction tombstone must not smuggle one in either.
  approval <- generator_store_read_approval(private_store, summary_data$contract_id)
  expect_identical(approval$approver, "(never approved)")
  expect_identical(approval$approved_at, "(never approved)")
  expect_match(approval$reason, "without prior approval", fixed = TRUE)

  expect_false(file.exists(
    generator_store_object_path(private_store, "generators", summary_data$generator_id)
  ))

  # Still idempotent, and still fails closed.
  again <- destroy_generator(store, summary_data$contract_id, "repeat")
  expect_identical(again$status, "destroyed")
  expect_error(
    generator_api_recover_frozen_handle(store, summary_data$contract_id),
    "destroyed"
  )
})

test_that("destroying a contract reports every fitted generator it removes", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  store <- file.path(tmp, "store")
  spec <- synth_spec("development", engine = "internal")

  # A contract is keyed by policy, not by source data, so freezing two
  # different datasets under one spec yields ONE contract with TWO fitted
  # generators. Destruction removes both; the caller must be able to see that.
  first <- summary(freeze_synthesis(
    data.frame(a = 1:10, b = 11:20, c = letters[1:10], stringsAsFactors = FALSE),
    spec, store = store
  ))
  second <- summary(freeze_synthesis(
    data.frame(a = 101:110, b = 201:210, c = LETTERS[1:10], stringsAsFactors = FALSE),
    spec, store = store
  ))
  expect_identical(first$contract_id, second$contract_id)
  expect_false(identical(first$generator_id, second$generator_id))

  destroyed <- destroy_generator(store, first$contract_id, "cleanup")

  expect_setequal(
    destroyed$generator_ids,
    c(first$generator_id, second$generator_id)
  )
  private_store <- generator_store_open(store)
  for (generator_id in c(first$generator_id, second$generator_id)) {
    expect_false(
      file.exists(generator_store_object_path(private_store, "generators", generator_id)),
      info = sprintf("generator %s removed", generator_id)
    )
  }
})
