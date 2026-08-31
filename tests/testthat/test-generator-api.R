local({
  api_fixture <- function() {
    data <- data.frame(
      amount = seq(100.123456, 139.123456, by = 1),
      offset = seq(400.654321, 439.654321, by = 1),
      group = rep(c("north", "south"), 20),
      flag = rep(c(TRUE, FALSE), 20),
      stringsAsFactors = FALSE
    )
    roles <- detect_roles(data)
    roles$simulation <- "synthesize"
    roles$identifies <- "none"
    roles$sensitive <- FALSE
    roles$user_identifies <- NA_character_
    roles$user_sensitive <- NA
    roles$user_role <- NA_character_
    roles$disclosure_role <- "none"
    spec <- synth_spec("demo", engine = "internal", k_anon = 2L)
    list(
      data = data,
      spec = spec,
      roles = roles,
      allowed = generation_limits(
        seed = c(1L, 1000L), n = c(20L, 100L), datasets = c(1L, 4L)
      )
    )
  }

  test_that("freeze creates a source-free public handle and contract", {
    fixture <- api_fixture()
    expect_error(
      freeze_synthesis(fixture$data, fixture$spec, fixture$roles,
        allowed = fixture$allowed),
      "explicit persistent"
    )
    store_path <- tempfile("dataganger-private-store-")
    frozen <- freeze_synthesis(
      fixture$data,
      fixture$spec,
      fixture$roles,
      allowed = fixture$allowed,
      store = store_path
    )

    expect_s3_class(frozen, "dataganger_frozen_generator")
    expect_s3_class(generator_contract(frozen), "dataganger_contract")
    expect_s3_class(generator_risk_report(frozen), "dataganger_generator_risk_report")
    expect_true(generator_risk_report(frozen)$eligible)
    expect_true(file.exists(file.path(store_path, ".dataganger-private-store.json")))
    expect_false("generator" %in% names(frozen))
    expect_false("data" %in% names(frozen))
    frozen_text <- paste(capture.output(dput(frozen)), collapse = "\n")
    expect_false(grepl("north", frozen_text, fixed = TRUE))
    expect_false(grepl("south", frozen_text, fixed = TRUE))
    expect_false(grepl("100.123456", frozen_text, fixed = TRUE))
  })

  test_that("approval is explicit and generation remains source-independent", {
    fixture <- api_fixture()
    store_path <- tempfile("dataganger-private-store-")
    frozen <- freeze_synthesis(
      fixture$data,
      fixture$spec,
      fixture$roles,
      allowed = fixture$allowed,
      store = store_path
    )

    expect_error(
      generate_synthetic(frozen, seed = 42L, n = 40L),
      class = "dataganger_generator_store_error"
    )
    approval <- approve_generator(
      frozen,
      approved_contract_id = generator_contract(frozen)$contract_id,
      approver = "Jax"
    )
    expect_s3_class(approval, "dataganger_approval")

    saved <- tempfile("dataganger-frozen-", fileext = ".rds")
    saveRDS(frozen, saved)
    rm(fixture)
    gc()
    reopened <- readRDS(saved)
    result <- generate_synthetic(reopened, seed = 42L, n = 40L)

    expect_s3_class(result, "dataganger_synthetic")
    expect_equal(nrow(result), 40L)
    expect_identical(attr(result, "generator_revision"), reopened$generator_revision)
    probe <- callr::r(function(path) {
      handle <- readRDS(path)
      c(
        root_exists = dir.exists(handle$store$root),
        marker_exists = file.exists(file.path(
          handle$store$root, ".dataganger-private-store.json"
        ))
      )
    }, args = list(path = saved))
    expect_identical(
      unname(probe),
      c(root_exists = TRUE, marker_exists = TRUE) |> unname()
    )
  })

  test_that("public API rejects policy and request mismatches", {
    fixture <- api_fixture()
    frozen <- freeze_synthesis(
      fixture$data,
      fixture$spec,
      fixture$roles,
      allowed = fixture$allowed,
      store = tempfile("dataganger-private-store-")
    )
    expect_error(
      approve_generator(frozen, approved_contract_id = strrep("a", 64L), approver = "Jax"),
      class = "dataganger_generator_error"
    )
    approve_generator(frozen, approver = "Jax")
    expect_error(
      generate_synthetic(frozen, seed = 1001L, n = 40L),
      class = "dataganger_generator_request_error"
    )
    expect_error(
      generate_synthetic(frozen, seed = 2L, n = 40L, datasets = 5L),
      class = "dataganger_generator_request_error"
    )
  })

  test_that("public receipts are sanitized and revocation is terminal", {
    fixture <- api_fixture()
    frozen <- freeze_synthesis(
      fixture$data, fixture$spec, fixture$roles,
      allowed = fixture$allowed,
      store = tempfile("dataganger-private-store-")
    )
    approve_generator(frozen, approver = "Jax")
    output <- generate_synthetic(frozen, seed = 42L, n = 40L)
    receipt <- generation_receipt(output)
    provenance <- attr(output, "generation_provenance")

    expect_s3_class(receipt, "dataganger_generation_receipt")
    expect_identical(receipt$receipt_type, "output")
    expect_identical(receipt$privacy, attr(output, "generation_privacy"))
    expect_named(receipt$privacy$kanon, c(
      "qi_cols", "k", "smallest_cell", "suppressed_cells", "suppressed_rows",
      "suppressed_row_frac", "infeasible"
    ))
    expect_identical(receipt$output_hash, generator_data_hash(output))
    expect_null(receipt$store)
    expect_null(receipt$generator_id)
    expect_null(receipt$approval_id)
    expect_null(receipt$approver)
    request_receipt <- generation_receipt(
      frozen, provenance$request_receipt_id[[1L]]
    )
    expect_identical(request_receipt$receipt_type, "request")

    revoked <- revoke_generator(frozen, "review policy changed")
    expect_identical(revoked$status, "revoked")
    expect_error(generate_synthetic(frozen, seed = 42L, n = 40L))
    expect_error(approve_generator(frozen, approver = "Jax"),
      "terminal approval status")
  })

  test_that("summary remains useful when the private store is unavailable", {
    fixture <- api_fixture()
    frozen <- freeze_synthesis(
      fixture$data, fixture$spec, fixture$roles,
      allowed = fixture$allowed,
      store = tempfile("dataganger-private-store-")
    )
    missing <- frozen
    missing$store$root <- tempfile("missing-dataganger-store-")
    info <- summary(missing)
    expect_false(info$store_available)
    expect_true(is.na(info$approved))
    expect_output(print(missing), "store available: FALSE")
  })

  test_that("frozen handles bind their displayed risk report to stored state", {
    fixture <- api_fixture()
    frozen <- freeze_synthesis(
      fixture$data, fixture$spec, fixture$roles,
      allowed = fixture$allowed,
      store = tempfile("dataganger-private-store-")
    )
    frozen$risk_report$warnings <- list(
      code = "altered_report",
      message = "This structurally valid report was not fitted.",
      column = NA_character_
    )
    expect_error(
      generator_risk_report(frozen),
      "does not match its stored generator",
      class = "dataganger_generator_tamper_error"
    )
  })

  test_that("privacy failures expose their durable request receipt ID", {
    fixture <- api_fixture()
    frozen <- freeze_synthesis(
      fixture$data, fixture$spec, fixture$roles,
      allowed = fixture$allowed,
      store = tempfile("dataganger-private-store-")
    )
    approve_generator(frozen, approver = "Jax")
    receipt_id <- strrep("a", 64L)
    testthat::local_mocked_bindings(
      generator_store_generate = function(...) {
        list(
          usable = FALSE,
          blockers = list(list(code = "privacy_postcondition")),
          receipt_id = receipt_id
        )
      }
    )
    error <- expect_error(
      generate_synthetic(frozen, seed = 42L, n = 40L),
      receipt_id,
      class = "dataganger_generator_privacy_error"
    )
    expect_identical(error$receipt_id, receipt_id)
  })
})
