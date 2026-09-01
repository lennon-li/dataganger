local({
  workspace_roles <- function(data) {
    roles <- detect_roles(data)
    roles$identifies <- "none"
    roles$sensitive <- FALSE
    roles$user_identifies <- NA_character_
    roles$user_sensitive <- NA
    roles
  }

  workspace_state <- function(data = data.frame(x = 1:20)) {
    list(
      raw_data = data,
      roles = workspace_roles(data),
      roles_confirmed = 1L,
      spec = synth_spec("demo", engine = "internal"),
      spec_confirmed = 1L,
      comparison = structure(list(ok = TRUE), class = "dataganger_comparison"),
      privacy = structure(list(ok = TRUE), class = "dataganger_privacy_check"),
      stale = list(synthesis = FALSE, comparison = FALSE, export = FALSE),
      generator_source_released = FALSE
    )
  }

  workspace_fixture <- function(root = tempfile("dataganger-workspace-store-")) {
    if (!dir.exists(root)) dir.create(root, recursive = TRUE)
    data <- data.frame(
      amount = seq(1.1, 40.1, by = 1),
      group = rep(c("north", "south"), 20),
      flag = rep(c(TRUE, FALSE), 20),
      stringsAsFactors = FALSE
    )
    roles <- workspace_roles(data)
    spec <- synth_spec("demo", engine = "internal", k_anon = 2L)
    frozen <- freeze_synthesis(
      data, spec, roles,
      allowed = generation_limits(
        seed = c(1L, 1000L), n = c(20L, 100L), datasets = c(1L, 2L)
      ),
      store = root
    )
    list(data = data, frozen = frozen, root = root)
  }

  test_that("default workspace store is the versioned R user data path", {
    expect_identical(
      generator_workspace_default_store(),
      file.path(tools::R_user_dir("dataganger", "data"), "generator-store-v1")
    )
  })

  test_that("readiness reports all required freeze blockers", {
    state <- list()
    readiness <- generator_workspace_readiness(state)
    expect_false(readiness$ready)
    expect_true(any(grepl("source data", readiness$blockers, fixed = TRUE)),
      info = paste(readiness$blockers, collapse = " | "))
    expect_true(any(grepl("roles", readiness$blockers, ignore.case = TRUE)),
      info = paste(readiness$blockers, collapse = " | "))
    expect_true(any(grepl("spec", readiness$blockers, ignore.case = TRUE)),
      info = paste(readiness$blockers, collapse = " | "))
    expect_true(any(grepl("comparison", readiness$blockers, ignore.case = TRUE)),
      info = paste(readiness$blockers, collapse = " | "))
    expect_true(any(grepl("privacy", readiness$blockers, ignore.case = TRUE)),
      info = paste(readiness$blockers, collapse = " | "))
    expect_true(any(grepl("internal", readiness$blockers, ignore.case = TRUE)),
      info = paste(readiness$blockers, collapse = " | "))
  })

  test_that("readiness requires explicit internal engine and fresh review", {
    state <- workspace_state()
    expect_true(generator_workspace_readiness(state)$ready)

    state$spec <- synth_spec("demo", engine = "auto")
    expect_false(generator_workspace_readiness(state)$ready)
    expect_true(any(grepl("internal", generator_workspace_readiness(state)$blockers)),
      info = paste(generator_workspace_readiness(state)$blockers, collapse = " | "))

    state <- workspace_state()
    state$spec <- synth_spec("demo", engine = "synthpop")
    expect_false(generator_workspace_readiness(state)$ready)
    expect_true(any(grepl("internal", generator_workspace_readiness(state)$blockers)),
      info = paste(generator_workspace_readiness(state)$blockers, collapse = " | "))

    state <- workspace_state()
    state$stale$comparison <- TRUE
    expect_false(generator_workspace_readiness(state)$ready)
    expect_true(any(grepl("comparison", generator_workspace_readiness(state)$blockers)),
      info = paste(generator_workspace_readiness(state)$blockers, collapse = " | "))

    state <- workspace_state()
    state$privacy <- NULL
    expect_false(generator_workspace_readiness(state)$ready)
    expect_true(any(grepl("privacy", generator_workspace_readiness(state)$blockers)),
      info = paste(generator_workspace_readiness(state)$blockers, collapse = " | "))
  })

  test_that("handle persistence is private, atomic, indexed, and revalidated", {
    fixture <- workspace_fixture()
    workspace_root <- withr::local_tempdir()
    saved <- generator_workspace_save_handle(fixture$frozen, workspace_root)
    expect_identical(saved$contract_id, fixture$frozen$contract_id)
    expect_true(file.exists(file.path(
      workspace_root, "handles", paste0(fixture$frozen$contract_id, ".rds")
    )))

    listing <- generator_workspace_list_handles(workspace_root)
    expect_length(listing, 1L)
    expect_identical(listing[[1L]]$contract_id, fixture$frozen$contract_id)
    listing_text <- paste(capture.output(dput(listing)), collapse = "\n")
    expect_false(grepl("generator_id", listing_text, fixed = TRUE))
    expect_false(grepl("store_id", listing_text, fixed = TRUE))
    expect_false(grepl(fixture$frozen$store$root, listing_text, fixed = TRUE))
    expect_identical(
      generator_workspace_load_handle(fixture$frozen$contract_id, workspace_root),
      fixture$frozen
    )
    expect_false(generator_workspace_handle_approved(fixture$frozen))
    approve_generator(
      fixture$frozen,
      approved_contract_id = fixture$frozen$contract_id,
      approver = "workspace-state-test"
    )
    expect_true(generator_workspace_handle_approved(fixture$frozen))
    expect_error(
      generator_workspace_load_handle("../private", workspace_root),
      class = "dataganger_generator_workspace_error"
    )

    handle_path <- file.path(
      workspace_root, "handles", paste0(fixture$frozen$contract_id, ".rds")
    )
    tampered <- readRDS(handle_path)
    tampered$contract_id <- strrep("a", 64L)
    saveRDS(tampered, handle_path)
    expect_error(
      generator_workspace_load_handle(fixture$frozen$contract_id, workspace_root),
      class = "dataganger_generator_validation_error"
    )
  })

  test_that("source release clears source state but preserves generator state", {
    state <- workspace_state()
    state$generator_draft <- list(engine = "internal")
    state$generator_active <- list(contract_id = strrep("a", 64L))
    state$generator_approval <- list(status = "approved")
    state$generator_result <- list(ok = TRUE)
    state$generator_receipts <- list(list(receipt_id = strrep("b", 64L)))
    state$generator_error <- "old error"
    state$generator_busy <- TRUE
    state$generator_store_root <- "/private/app/store"

    released <- generator_workspace_release_source(state)
    expect_null(released$raw_data)
    expect_null(released$roles)
    expect_null(released$spec)
    expect_null(released$comparison)
    expect_null(released$privacy)
    expect_null(released$generator_draft)
    expect_true(released$generator_source_released)
    expect_identical(released$generator_active, state$generator_active)
    expect_identical(released$generator_approval, state$generator_approval)
    expect_identical(released$generator_result, state$generator_result)
    expect_identical(released$generator_receipts, state$generator_receipts)
    expect_identical(released$generator_store_root, state$generator_store_root)
    expect_false(released$generator_busy)
    expect_null(released$generator_error)
  })

  test_that("generator privacy details normalize for export interfaces", {
    flags <- generator_workspace_privacy_flags(list(
      exact_match_count = 1L,
      blockers = list(
        code = "exact_row_match",
        message = "Generated output contains a source row.",
        column = NA_character_
      )
    ))

    expect_true(is.data.frame(flags))
    expect_identical(flags$severity[[1L]], "high")
    expect_identical(attr(flags, "exact_row_matches"), 1L)
  })

  test_that("reset clears isolated generator state without deleting its store", {
    root <- withr::local_tempdir()
    state <- list(
      generator_draft = list(source = "private"),
      generator_active = list(contract_id = strrep("a", 64L)),
      generator_approval = list(status = "approved"),
      generator_result = list(ok = TRUE),
      generator_receipts = list(list(receipt_id = strrep("b", 64L))),
      generator_error = "error",
      generator_busy = TRUE,
      generator_source_released = TRUE,
      generator_store_root = root
    )
    marker <- file.path(root, "keep-me")
    writeLines("durable", marker)

    reset <- generator_workspace_reset(state)
    expect_null(reset$generator_draft)
    expect_null(reset$generator_active)
    expect_null(reset$generator_approval)
    expect_null(reset$generator_result)
    expect_identical(reset$generator_receipts, list())
    expect_null(reset$generator_error)
    expect_false(reset$generator_busy)
    expect_false(reset$generator_source_released)
    expect_identical(reset$generator_store_root, generator_workspace_default_store())
    expect_true(file.exists(marker))
  })

  test_that("release and reset accept reactiveValues state", {
    testthat::skip_if_not_installed("shiny")

    state <- shiny::reactiveValues(
      raw_data = data.frame(x = 1:3),
      roles = data.frame(variable = "x"),
      spec = synth_spec("demo", engine = "internal"),
      comparison = list(ok = TRUE),
      privacy = list(ok = TRUE),
      generator_active = list(contract_id = strrep("a", 64L)),
      generator_receipts = list(list(receipt_id = strrep("b", 64L))),
      generator_store_root = withr::local_tempdir()
    )

    generator_workspace_release_source(state)
    shiny::isolate({
      expect_null(state$raw_data)
      expect_identical(state$generator_active$contract_id, strrep("a", 64L))
      expect_true(state$generator_source_released)
    })

    generator_workspace_reset(state)
    shiny::isolate({
      expect_null(state$generator_active)
      expect_identical(state$generator_receipts, list())
      expect_false(state$generator_source_released)
    })
  })
})
