local({
  store_fixture <- function() {
    data <- data.frame(
      amount = seq(1.1, 40.1, by = 1),
      group = rep(c("north", "south"), 20),
      flag = rep(c(TRUE, FALSE), 20),
      stringsAsFactors = FALSE
    )
    roles <- detect_roles(data)
    roles$disclosure_role <- "none"
    roles$identifies <- "none"
    roles$sensitive <- FALSE
    roles$user_identifies <- NA_character_
    roles$user_sensitive <- NA
    roles$user_role <- NA_character_
    roles$simulation <- "synthesize"
    generator <- fit_internal_generator(
      data,
      synth_spec("demo", engine = "internal", k_anon = 2),
      roles
    )
    contract <- generator_contract(
      policy = generator_derive_policy(generator),
      allowed = generation_limits(
        seed = c(1L, 1000L), n = c(20L, 100L), datasets = c(1L, 3L)
      ),
      compatibility = generator_derive_compatibility()
    )
    store_path <- tempfile("dataganger-store-")
    dir.create(store_path)
    store <- generator_store_create(store_path)
    record <- generator_store_put_generator(store, generator)
    list(store = store, generator = generator, contract = contract, record = record)
  }

  test_that("private stores are marked, opaque, and restrictive", {
    path <- withr::local_tempdir()
    store <- generator_store_create(path)
    reopened <- generator_store_open(path)

    expect_s3_class(store, "dataganger_generator_store")
    expect_identical(store$store_id, reopened$store_id)
    expect_true(file.exists(file.path(path, ".dataganger-private-store.json")))
    expect_identical(
      dir.exists(file.path(path, generator_store_dirs())),
      rep(TRUE, length(generator_store_dirs()))
    )
    expect_error(
      generator_store_open(withr::local_tempdir()),
      class = "dataganger_generator_store_error"
    )
    if (.Platform$OS.type == "unix") {
      expect_match(format(file.info(path)$mode), "700$")
    }
  })

  test_that("failed atomic writes leave no temporary approved object", {
    path <- withr::local_tempdir()
    store <- generator_store_create(path)
    target <- file.path(store$root, "contracts", paste0(strrep("a", 64L), ".json"))
    dir.create(target)
    expect_error(
      suppressWarnings(generator_store_atomic_write(target, "partial")),
      class = "dataganger_generator_store_error"
    )
    expect_true(dir.exists(target))
    expect_length(
      list.files(store$root, pattern = "^\\.dataganger-write-", recursive = TRUE),
      0L
    )
  })

  test_that("private generator round trips through a tagged non-RDS envelope", {
    fixture <- store_fixture()
    record <- fixture$record
    restored <- generator_store_read_generator(fixture$store, record$generator_id)

    expect_s3_class(record, "dataganger_private_generator_record")
    expect_identical(
      generator_store_generator_fingerprint(restored),
      record$generator_fingerprint
    )
    expect_identical(
      generator_runtime_revision_id(restored),
      record$generator_revision
    )
    expect_true(generator_fitted_state_audit(restored)$clean)
    stored_names <- paste(list.files(fixture$store$root, recursive = TRUE), collapse = "\n")
    expect_false(grepl("RDS", stored_names))
    expect_error(
      generator_store_read_generator(fixture$store, tempfile()),
      class = "dataganger_generator_store_error"
    )
  })

  test_that("approval binds contract, generator, limits, compiler, and risk", {
    fixture <- store_fixture()
    generator_store_approve(
      fixture$store,
      fixture$contract,
      fixture$record$generator_id,
      approver = "Liz"
    )
    active <- generator_store_validate_active_approval(
      fixture$store,
      fixture$contract$contract_id
    )

    expect_identical(active$approval$contract_id, fixture$contract$contract_id)
    expect_identical(active$approval$generator_id, fixture$record$generator_id)
    expect_identical(active$approval$allowed, unclass(fixture$contract$allowed))
    expect_identical(active$approval$generator_fingerprint, fixture$record$generator_fingerprint)
    expect_identical(
      active$approval$binding_hash,
      generator_store_approval_binding(active$approval)
    )
  })

  test_that("approved generation creates an auditable receipt and enforces bounds", {
    fixture <- store_fixture()
    generator_store_approve(
      fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
    )
    result <- generator_store_generate(
      fixture$store,
      fixture$contract$contract_id,
      seed = 17L,
      n = 40L,
      datasets = 2L
    )
    receipt <- generator_store_read_receipt(fixture$store, result$receipt_id)
    output_receipts <- lapply(result$receipt_ids, function(id) {
      generator_store_read_receipt(fixture$store, id)
    })

    expect_identical(result$approval_id, receipt$approval_id)
    expect_identical(receipt$request_id, result$request_id)
    expect_length(receipt$seeds, 2L)
    expect_length(receipt$output_hashes, 2L)
    expect_identical(receipt$receipt_type, "request")
    expect_identical(receipt$output_receipt_ids, result$receipt_ids)
    expect_identical(
      vapply(output_receipts, `[[`, character(1L), "receipt_type"),
      rep("output", 2L)
    )
    expect_identical(
      vapply(output_receipts, `[[`, character(1L), "output_hash"),
      vapply(result$outputs, generator_data_hash, character(1L))
    )
    expect_identical(receipt$contract_id, fixture$contract$contract_id)
    expect_identical(receipt$generator_id, fixture$record$generator_id)
    expect_true(is.logical(receipt$usable))
    expect_error(
      generator_store_generate(fixture$store, fixture$contract$contract_id, seed = 2L, n = 101L),
      class = "dataganger_generator_request_error"
    )
    stored_text <- paste(vapply(
      list.files(fixture$store$root, recursive = TRUE, full.names = TRUE),
      function(path) paste(readLines(path, warn = FALSE), collapse = ""),
      character(1L)
    ), collapse = "\n")
    expect_false(grepl("source data|source_vector", stored_text))
  })

  test_that("contract edits and generator replacement fail closed", {
    fixture <- store_fixture()
    generator_store_approve(
      fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
    )

    contract_path <- generator_store_object_path(
      fixture$store, "contracts", fixture$contract$contract_id
    )
    contract_text <- paste(readLines(contract_path, warn = FALSE), collapse = "")
    tampered <- sub("internal", "changed", contract_text, fixed = TRUE)
    writeLines(tampered, contract_path, useBytes = TRUE)
    expect_error(
      generator_store_generate(fixture$store, fixture$contract$contract_id, seed = 42L, n = 40L),
      class = "dataganger_generator_store_tamper_error"
    )

    fixture <- store_fixture()
    generator_store_approve(
      fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
    )
    replacement <- fixture$generator
    replacement$settings$k_anon <- 3L
    expect_error(
      generator_store_replace_generator(
        fixture$store, fixture$record$generator_id, replacement
      ),
      class = "dataganger_generator_store_error"
    )
  })

  test_that("metadata migration preserves approval but semantic migration requires reapproval", {
    fixture <- store_fixture()
    generator_store_approve(
      fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
    )
    expect_invisible(generator_store_update_metadata(
      fixture$store,
      fixture$record$generator_id,
      list(note = "read-only operator metadata")
    ))
    expect_identical(
      generator_store_validate_active_approval(fixture$store, fixture$contract$contract_id)$approval$status,
      "approved"
    )

    changed <- fixture$generator
    changed$settings$k_anon <- 3L
    expect_error(
      generator_store_migrate_generator(
        fixture$store, fixture$record$generator_id, changed
      ),
      class = "dataganger_generator_store_error"
    )
  })

  test_that("revocation and supersession disable old approvals", {
    fixture <- store_fixture()
    generator_store_approve(
      fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
    )
    generator_store_revoke(fixture$store, fixture$contract$contract_id, "policy changed")
    expect_error(
      generator_store_approve(
        fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
      ),
      "terminal approval status"
    )
    expect_error(
      generator_store_generate(fixture$store, fixture$contract$contract_id, seed = 42L, n = 40L),
      class = "dataganger_generator_store_error"
    )

    fixture <- store_fixture()
    second <- generator_contract(
      policy = generator_derive_policy(fixture$generator),
      allowed = generation_limits(
        seed = c(1L, 900L), n = c(20L, 100L), datasets = c(1L, 3L)
      ),
      compatibility = generator_derive_compatibility()
    )
    generator_store_approve(fixture$store, fixture$contract, fixture$record$generator_id, "Liz")
    generator_store_approve(fixture$store, second, fixture$record$generator_id, "Liz")
    expect_invisible(generator_store_supersede(
      fixture$store, fixture$contract$contract_id, second$contract_id
    ))
    expect_error(
      generator_store_generate(fixture$store, fixture$contract$contract_id, seed = 42L, n = 40L),
      class = "dataganger_generator_store_error"
    )
    expect_identical(
      generator_store_read_approval(fixture$store, fixture$contract$contract_id)$status,
      "superseded"
    )
    expect_error(
      generator_store_approve(
        fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
      ),
      "terminal approval status"
    )
  })

  test_that("approval is idempotent and rejects a mismatched generator contract", {
    fixture <- store_fixture()
    first <- generator_store_approve(
      fixture$store, fixture$contract, fixture$record$generator_id, "Liz"
    )
    second <- generator_store_approve(
      fixture$store, fixture$contract, fixture$record$generator_id, "Someone else"
    )
    expect_identical(first$approval_id, second$approval_id)

    mismatched <- generator_contract(
      policy = modifyList(generator_derive_policy(fixture$generator), list(
        output_names = "wrong"
      )),
      allowed = fixture$contract$allowed,
      compatibility = generator_derive_compatibility()
    )
    expect_error(
      generator_store_approve(
        fixture$store, mismatched, fixture$record$generator_id, "Liz"
      ),
      "not derived"
    )
  })
})
