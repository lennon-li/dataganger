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

  destroyed <- destroy_generator(fixture$store, fixture$contract_id, "retention policy")
  expect_identical(destroyed$status, "destroyed")
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
