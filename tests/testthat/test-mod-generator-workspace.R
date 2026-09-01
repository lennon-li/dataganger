local({
  workspace_fake_frozen <- function(
      contract_id = strrep("a", 64L),
      n = c(1L, 100L),
      datasets = c(1L, 3L)) {
    allowed <- generation_limits(
      seed = c(0L, .Machine$integer.max),
      n = n,
      datasets = datasets
    )
    structure(
      list(
        contract_id = contract_id,
        contract = structure(list(
          contract_id = contract_id,
          allowed = allowed,
          policy = list(
            naming = list(strategy = "preserve"),
            columns = list(x = list(simulation = "resample"))
          ),
          compatibility = list(package = "dataganger")
        ), class = "dataganger_contract"),
        risk_report = structure(list(
          eligible = TRUE,
          blockers = data.frame(code = character(), detail = character()),
          warnings = data.frame(code = "review", detail = "Review this policy.")
        ), class = "dataganger_generator_risk_report")
      ),
      class = "dataganger_frozen_generator"
    )
  }

  workspace_test_state <- function(active = FALSE) {
    frozen <- workspace_fake_frozen()
    shiny::reactiveValues(
      raw_data = data.frame(x = 1:5),
      spec = synth_spec("demo", engine = "internal"),
      roles = structure(data.frame(variable = "x"), class = c(
        "dataganger_roles", "data.frame"
      )),
      generator_draft = if (active) NULL else NULL,
      generator_draft_token = NULL,
      generator_active = if (active) frozen else NULL,
      generator_approval = if (active) {
        list(status = "approved", contract_id = frozen$contract_id)
      } else {
        NULL
      },
      generator_export_spec = NULL,
      generator_export_roles = NULL,
      generator_export_privacy = NULL,
      generator_result = NULL,
      generator_receipts = list(),
      generator_error = NULL,
      generator_busy = FALSE,
      generator_source_released = FALSE,
      generator_store_root = "/private/workspace",
      synthetic = NULL,
      comparison = NULL,
      privacy = NULL,
      stale = list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    )
  }

  test_that("generator workspace UI states the local security boundary", {
    html <- as.character(mod_generator_workspace_ui("generator"))

    expect_match(html, "Reusable generators", fixed = TRUE)
    expect_match(html, "stored locally", fixed = TRUE)
    expect_match(html, "Releasing source data removes it from this app session", fixed = TRUE)
    expect_match(html, "workspace_actions", fixed = TRUE)
    expect_match(html, "generator-workspace", fixed = TRUE)
  })

  test_that("fitted risk and request bounds are shown to the human reviewer", {
    report <- structure(list(
      eligible = TRUE,
      blockers = data.frame(code = character(), detail = character()),
      warnings = data.frame(code = "review", detail = "Review this policy.")
    ), class = "dataganger_generator_risk_report")
    frozen <- workspace_fake_frozen(n = c(1L, 25L), datasets = c(1L, 2L))

    report_html <- as.character(render_generator_risk_report(report))
    bounds_html <- as.character(render_generator_bounds(frozen))

    expect_match(report_html, "Fitted-state risk review", fixed = TRUE)
    expect_match(report_html, "Review this policy", fixed = TRUE)
    expect_match(bounds_html, "Approved request bounds", fixed = TRUE)
    expect_match(bounds_html, "Rows per dataset: 1 to 25", fixed = TRUE)
    expect_match(bounds_html, "Datasets per request: 1 to 2", fixed = TRUE)
  })

  test_that("freeze is gated and preserves the explicit internal spec", {
    state <- workspace_test_state()
    calls <- list()
    frozen <- workspace_fake_frozen()

    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = TRUE, blockers = character(), warnings = "Review bounds.")
      },
      freeze_synthesis = function(data, spec, roles, allowed, store) {
        calls[[length(calls) + 1L]] <<- list(
          data = data, spec = spec, roles = roles, allowed = allowed, store = store
        )
        frozen
      },
      generator_workspace_save_handle = function(frozen, root) {
        list(contract_id = frozen$contract_id, root = root)
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(
        freeze_max_n = 250L,
        freeze_max_datasets = 4L,
        freeze = 1L
      )
      session$flushReact()
    })

    expect_length(calls, 1L)
    expect_identical(calls[[1L]]$spec$engine, "internal")
    expect_identical(calls[[1L]]$store, "/private/workspace/private-store")
    expect_identical(calls[[1L]]$allowed$seed, c(0L, .Machine$integer.max))
    expect_identical(calls[[1L]]$allowed$n, c(1L, 250L))
    expect_identical(calls[[1L]]$allowed$datasets, c(1L, 4L))
    expect_identical(shiny::isolate(state$generator_draft), frozen)
    expect_null(shiny::isolate(state$generator_error))
  })

  test_that("freeze does not run when readiness has blockers", {
    state <- workspace_test_state()
    freeze_calls <- 0L
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = "Privacy review is stale.", warnings = character())
      },
      freeze_synthesis = function(...) {
        freeze_calls <<- freeze_calls + 1L
        workspace_fake_frozen()
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(freeze = 1L)
      session$flushReact()
      expect_identical(view(), "no_eligible_draft")
    })

    expect_identical(freeze_calls, 0L)
    expect_match(shiny::isolate(state$generator_error$message), "Privacy review is stale")
  })

  test_that("approval requires an exact contract ID", {
    state <- workspace_test_state()
    frozen <- workspace_fake_frozen()
    state$generator_draft <- frozen
    state$generator_draft_token <- shiny::isolate(
      generator_workspace_policy_token(state)
    )
    approvals <- list()
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = TRUE, blockers = character(), warnings = character())
      },
      approve_generator = function(frozen, approved_contract_id, approver) {
        approvals[[length(approvals) + 1L]] <<- list(
          contract_id = approved_contract_id,
          approver = approver
        )
        list(status = "approved", contract_id = approved_contract_id)
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(
        approval_contract_id = "wrong",
        approver = "Lennon",
        approve = 1L
      )
      session$flushReact()
      expect_identical(view(), "frozen_unapproved")

      session$setInputs(
        approval_contract_id = frozen$contract_id,
        approve = 2L
      )
      session$flushReact()
      expect_identical(view(), "approved")
    })

    expect_length(approvals, 1L)
    expect_identical(approvals[[1L]]$contract_id, frozen$contract_id)
    expect_identical(shiny::isolate(state$generator_active), frozen)
    expect_null(shiny::isolate(state$generator_draft))
  })

  test_that("approval rechecks current readiness", {
    state <- workspace_test_state()
    frozen <- workspace_fake_frozen()
    state$generator_draft <- frozen
    state$generator_draft_token <- shiny::isolate(
      generator_workspace_policy_token(state)
    )
    approvals <- 0L
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = "Privacy review is stale.", warnings = character())
      },
      approve_generator = function(...) {
        approvals <<- approvals + 1L
        list(status = "approved")
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(
        approval_contract_id = frozen$contract_id,
        approver = "Lennon",
        approve = 1L
      )
      session$flushReact()
    })

    expect_identical(approvals, 0L)
    expect_match(shiny::isolate(state$generator_error$message), "Privacy review is stale")
    expect_null(shiny::isolate(state$generator_active))
  })

  test_that("approved workspace disables frozen mutation controls", {
    state <- workspace_test_state(active = TRUE)

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$flushReact()
      html <- paste(as.character(output$workspace_actions), collapse = "\n")
      expect_match(html, "disabled", fixed = TRUE)
      expect_match(html, "Generate variation", fixed = TRUE)
    })
  })

  test_that("source release preserves the approved generator", {
    state <- workspace_test_state(active = TRUE)
    active <- shiny::isolate(state$generator_active)
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = character(), warnings = character())
      },
      generator_workspace_release_source = function(state) {
        state$raw_data <- NULL
        state$generator_source_released <- TRUE
        state
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(release_source = 1L)
      session$flushReact()
    })

    expect_null(shiny::isolate(state$raw_data))
    expect_true(shiny::isolate(state$generator_source_released))
    expect_identical(shiny::isolate(state$generator_active), active)
    expect_identical(shiny::isolate(state$generator_approval$status), "approved")
  })

  test_that("editing the six-step policy creates an explicit fresh-review revision", {
    state <- workspace_test_state(active = TRUE)
    active <- shiny::isolate(state$generator_active)
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = "Review the changed policy.", warnings = character())
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$flushReact()
      state$spec <- synth_spec("demo", engine = "internal", k_anon = 4L)
      session$flushReact()
      expect_identical(view(), "policy_revision")
    })

    expect_identical(shiny::isolate(state$generator_active), active)
    expect_true(is.list(shiny::isolate(state$generator_draft)))
    expect_identical(shiny::isolate(state$generator_draft$spec$k_anon), 4L)
  })

  test_that("editing policy replaces a frozen draft before approval", {
    state <- workspace_test_state(active = TRUE)
    frozen <- workspace_fake_frozen()
    state$generator_draft <- frozen
    state$generator_draft_token <- shiny::isolate(
      generator_workspace_policy_token(state)
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$flushReact()
      state$spec <- synth_spec("demo", engine = "internal", k_anon = 3L)
      session$flushReact()
      expect_identical(view(), "policy_revision")
    })

    expect_false(inherits(shiny::isolate(state$generator_draft),
      "dataganger_frozen_generator"))
    expect_identical(
      shiny::isolate(state$generator_draft$spec$k_anon),
      3L
    )
  })

  test_that("source release is unavailable before approval", {
    state <- workspace_test_state()
    state$generator_draft <- workspace_fake_frozen()
    release_calls <- 0L
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = character(), warnings = character())
      },
      generator_workspace_release_source = function(state) {
        release_calls <<- release_calls + 1L
        state
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(release_source = 1L)
      session$flushReact()
    })

    expect_identical(release_calls, 0L)
    expect_match(
      shiny::isolate(state$generator_error$message),
      "Approve a generator"
    )
  })

  test_that("generation requests are rejected outside contract bounds", {
    state <- workspace_test_state(active = TRUE)
    calls <- 0L
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = character(), warnings = character())
      },
      generate_synthetic = function(...) {
        calls <<- calls + 1L
        structure(data.frame(x = 1L), class = c("dataganger_synthetic", "data.frame"))
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(request_seed = 1L, request_n = 101L, request_datasets = 1L)
      session$setInputs(generate = 1L)
      session$flushReact()
      expect_null(selected_output())
    })

    expect_identical(calls, 0L)
    expect_match(shiny::isolate(state$generator_error$message), "approved bounds")
    expect_null(shiny::isolate(state$generator_result))
  })

  test_that("failed generation clears output and exposes its durable receipt ID", {
    state <- workspace_test_state(active = TRUE)
    state$synthetic <- structure(
      data.frame(old = 1L), class = c("dataganger_synthetic", "data.frame")
    )
    receipt_id <- strrep("b", 64L)
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = character(), warnings = character())
      },
      generate_synthetic = function(...) {
        condition <- structure(
          list(message = "privacy postcondition failed", receipt_id = receipt_id),
          class = c("dataganger_generator_privacy_error", "error", "condition")
        )
        stop(condition)
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(request_seed = 1L, request_n = 10L, request_datasets = 1L)
      session$setInputs(generate = 1L)
      session$flushReact()
      expect_null(selected_output())
    })

    expect_null(shiny::isolate(state$generator_result))
    expect_null(shiny::isolate(state$synthetic))
    expect_identical(shiny::isolate(state$generator_error$receipt_id), receipt_id)
    expect_identical(
      shiny::isolate(state$generator_receipts[[1L]]$receipt_id),
      receipt_id
    )
  })

  test_that("batch selection keeps output receipts and requires explicit export use", {
    state <- workspace_test_state(active = TRUE)
    receipt_one <- structure(list(receipt_id = strrep("c", 64L)),
      class = "dataganger_generation_receipt")
    receipt_two <- structure(list(receipt_id = strrep("d", 64L)),
      class = "dataganger_generation_receipt")
    output_one <- structure(data.frame(x = 1L),
      class = c("dataganger_synthetic", "data.frame"))
    output_two <- structure(data.frame(x = 2L),
      class = c("dataganger_synthetic", "data.frame"))
    attr(output_one, "generation_receipt") <- receipt_one
    attr(output_two, "generation_receipt") <- receipt_two
    attr(output_two, "generation_privacy") <- list(
      ok = TRUE,
      exact_match_count = 0L,
      kanon = list(suppressed_rows = 1L)
    )
    batch <- generator_batch(
      outputs = list(output_one, output_two),
      seeds = c(10L, 11L),
      provenance = data.frame(
        dataset = 1:2,
        seed = c(10L, 11L),
        receipt_id = c(receipt_one$receipt_id, receipt_two$receipt_id)
      ),
      privacy = list(list(ok = TRUE), list(ok = TRUE)),
      diagnostics = list(list(), list()),
      request_id = strrep("e", 64L),
      contract_id = shiny::isolate(state$generator_active$contract_id),
      generator_revision = strrep("f", 64L),
      receipt_id = strrep("1", 64L),
      receipt_ids = c(receipt_one$receipt_id, receipt_two$receipt_id)
    )
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = character(), warnings = character())
      },
      generate_synthetic = function(...) batch,
      generation_receipt = function(x, receipt_id = NULL) list(receipt_one, receipt_two)
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(request_seed = 10L, request_n = 10L, request_datasets = 2L)
      session$setInputs(generate = 1L)
      session$flushReact()
      expect_null(shiny::isolate(state$synthetic))

      session$setInputs(selected_dataset = "2")
      session$setInputs(use_selected = 1L)
      session$flushReact()
      expect_identical(selected_output(), output_two)
    })

    expect_identical(shiny::isolate(state$synthetic), output_two)
    expect_identical(
      attr(shiny::isolate(state$synthetic), "generation_receipt")$receipt_id,
      receipt_two$receipt_id
    )
    expect_identical(shiny::isolate(state$privacy)$kanon$suppressed_rows, 1L)
    expect_null(shiny::isolate(state$comparison))
    expect_length(shiny::isolate(state$generator_receipts), 2L)
  })

  test_that("saved handles are loaded only through the revalidating helper", {
    state <- workspace_test_state()
    contract_id <- strrep("9", 64L)
    frozen <- workspace_fake_frozen(contract_id)
    loaded <- character()
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = character(), warnings = character())
      },
      generator_workspace_list_handles = function(root) {
        list(list(contract_id = contract_id, saved_at = "now"))
      },
      generator_workspace_load_handle = function(id, root) {
        loaded <<- c(loaded, id)
        frozen
      },
      generator_workspace_backend_approval = function(frozen) {
        list(status = "approved", contract_id = frozen$contract_id)
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(saved_contract = contract_id, load_saved = 1L)
      session$flushReact()
      expect_identical(view(), "approved")
    })

    expect_identical(loaded, contract_id)
    expect_identical(shiny::isolate(state$generator_active), frozen)
    expect_identical(shiny::isolate(state$generator_approval$status), "approved")
  })

  test_that("revocation requires a reason and clears reusable output", {
    state <- workspace_test_state(active = TRUE)
    state$generator_result <- list(outputs = list(data.frame(x = 1L)))
    state$synthetic <- data.frame(x = 1L)
    reasons <- character()
    testthat::local_mocked_bindings(
      generator_workspace_readiness = function(state) {
        list(ready = FALSE, blockers = character(), warnings = character())
      },
      revoke_generator = function(frozen, reason) {
        reasons <<- c(reasons, reason)
        list(status = "revoked", reason = reason, contract_id = frozen$contract_id)
      }
    )

    shiny::testServer(mod_generator_workspace_server, args = list(state = state), {
      session$setInputs(revoke_reason = "", revoke = 1L)
      session$flushReact()
      expect_identical(view(), "approved")

      session$setInputs(revoke_reason = "Policy changed", revoke = 2L)
      session$flushReact()
      expect_identical(view(), "revoked_error")
    })

    expect_identical(reasons, "Policy changed")
    expect_identical(shiny::isolate(state$generator_approval$status), "revoked")
    expect_null(shiny::isolate(state$generator_result))
    expect_null(shiny::isolate(state$synthetic))
  })
})
