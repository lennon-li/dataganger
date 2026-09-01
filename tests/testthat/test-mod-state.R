test_that("new upload resets downstream state and clears stale flags", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(mod_state_server, {
    state <- session$getReturned()

    state$roles <- tibble::tibble(variable = "x", user_role = "measure")
    state$spec <- list(purpose = "development")
    state$synthetic <- tibble::tibble(x = 1)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = TRUE, comparison = TRUE, export = TRUE)

    state$raw_data <- tibble::tibble(x = 1:3)
    session$flushReact()

    expect_s3_class(state$raw_data, "data.frame")
    expect_null(state$profile)
    expect_null(state$roles)
    expect_null(state$spec)
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
    expect_identical(
      state$stale,
      list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    )
  })
})

test_that("roles change invalidates downstream state and marks all stale", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(mod_state_server, {
    state <- session$getReturned()

    state$raw_data <- tibble::tibble(x = 1:3)
    session$flushReact()

    state$roles <- tibble::tibble(variable = "x", user_role = "measure")
    session$flushReact()

    state$spec <- list(purpose = "development")
    state$synthetic <- NULL
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)

    state$roles <- tibble::tibble(variable = "x", user_role = "identifier")
    session$flushReact()

    expect_null(state$spec)
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
    expect_true(isTRUE(state$stale$synthesis))
    expect_true(isTRUE(state$stale$comparison))
    expect_true(isTRUE(state$stale$export))
  })
})

test_that("spec change invalidates synthesis outputs and marks all stale", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(mod_state_server, {
    state <- session$getReturned()

    state$raw_data <- tibble::tibble(x = 1:3)
    session$flushReact()

    state$roles <- tibble::tibble(variable = "x", user_role = "measure")
    session$flushReact()

    state$spec <- list(purpose = "development")
    session$flushReact()

    state$synthetic <- tibble::tibble(x = 4:6)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)

    state$spec <- list(purpose = "demo")
    session$flushReact()

    expect_identical(state$spec, list(purpose = "demo"))
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
    expect_true(isTRUE(state$stale$synthesis))
    expect_true(isTRUE(state$stale$comparison))
    expect_true(isTRUE(state$stale$export))
  })
})


test_that("state initializes active_step and compare_selected_var", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(mod_state_server, {
    state <- session$getReturned()
    expect_identical(state$active_step, "upload")
    expect_null(state$compare_selected_var)
    expect_null(state$generator_draft)
    expect_null(state$generator_active)
    expect_null(state$generator_approval)
    expect_null(state$generator_result)
    expect_identical(state$generator_receipts, list())
    expect_null(state$generator_error)
    expect_false(state$generator_busy)
    expect_false(state$generator_source_released)
    expect_identical(
      state$generator_store_root,
      generator_workspace_default_store()
    )
  })
})

test_that("upload reset does not clear isolated generator state", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(mod_state_server, {
    state <- session$getReturned()
    active <- list(contract_id = strrep("a", 64L))
    state$generator_draft <- list(engine = "internal")
    state$generator_active <- active
    state$generator_approval <- list(status = "approved")
    state$generator_result <- list(ok = TRUE)
    state$generator_receipts <- list(list(receipt_id = strrep("b", 64L)))
    state$generator_error <- "old error"
    state$generator_busy <- TRUE
    state$generator_source_released <- TRUE
    state$generator_store_root <- withr::local_tempdir()

    state$raw_data <- tibble::tibble(x = 1:3)
    session$flushReact()

    expect_identical(state$generator_draft, list(engine = "internal"))
    expect_identical(state$generator_active, active)
    expect_identical(state$generator_approval, list(status = "approved"))
    expect_identical(state$generator_result, list(ok = TRUE))
    expect_identical(
      state$generator_receipts,
      list(list(receipt_id = strrep("b", 64L)))
    )
    expect_identical(state$generator_error, "old error")
    expect_true(state$generator_busy)
    expect_true(state$generator_source_released)
  })
})
