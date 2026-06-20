generate_test_state <- function(data = NULL, spec = NULL) {
  shiny::reactiveValues(
    raw_data = data,
    spec = spec,
    synthetic = NULL,
    comparison = NULL,
    privacy = NULL,
    seed_used = NULL,
    nav_request = NULL,
    stale = list(
      synthesis = TRUE,
      comparison = TRUE,
      export = TRUE
    )
  )
}

capture_notifications <- function() {
  notifications <- list()

  list(
    options = list(
      dataganger.generate_notification_hook = function(args) {
        notifications[[length(notifications) + 1]] <<- list(
          ui = args[[1]],
          duration = if (is.null(args$duration)) 5 else args$duration,
          type = if (is.null(args$type)) "default" else args$type
        )
      }
    ),
    get = function() notifications
  )
}

test_that("generate warns when state raw_data is NULL", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(spec = synth_spec(purpose = "development"))
  recorder <- capture_notifications()
  withr::local_options(recorder$options)

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  notifications <- recorder$get()
  expect_length(notifications, 1)
  expect_identical(notifications[[1]]$ui, "No data or spec available.")
  expect_identical(notifications[[1]]$type, "warning")
  expect_null(shiny::isolate(state$synthetic))
})

test_that("generate warns when state spec is NULL", {
  testthat::skip_if_not_installed("shiny")

  data("example_health_survey", package = "dataganger")
  state <- generate_test_state(data = example_health_survey, spec = NULL)
  recorder <- capture_notifications()
  withr::local_options(recorder$options)

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  notifications <- recorder$get()
  expect_length(notifications, 1)
  expect_identical(notifications[[1]]$ui, "No data or spec available.")
  expect_identical(notifications[[1]]$type, "warning")
  expect_null(shiny::isolate(state$synthetic))
})

test_that("successful generation populates synthetic outputs", {
  testthat::skip_if_not_installed("shiny")

  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "development", seed = 1)
  state <- generate_test_state(data = example_health_survey, spec = spec)

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  expect_s3_class(shiny::isolate(state$synthetic), "dataganger_synthetic")
  expect_s3_class(shiny::isolate(state$comparison), "dataganger_comparison")
  expect_s3_class(shiny::isolate(state$privacy), "dataganger_privacy_check")
  expect_false(is.null(attr(shiny::isolate(state$privacy), "exact_row_matches", exact = TRUE)))
})

test_that("successful generation clears stale flags", {
  testthat::skip_if_not_installed("shiny")

  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "development", seed = 2)
  state <- generate_test_state(data = example_health_survey, spec = spec)

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  stale <- shiny::isolate(state$stale)
  expect_false(isTRUE(stale$synthesis))
  expect_false(isTRUE(stale$comparison))
  expect_false(isTRUE(stale$export))
})

test_that("synthesis errors notify and leave state untouched", {
  testthat::skip_if_not_installed("shiny")

  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "development", seed = 3)
  state <- generate_test_state(data = example_health_survey, spec = spec)
  recorder <- capture_notifications()
  withr::local_options(recorder$options)
  testthat::local_mocked_bindings(synthesize_data = function(...) stop("kaboom", call. = FALSE))

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  notifications <- recorder$get()
  expect_length(notifications, 1)
  expect_match(notifications[[1]]$ui, "^Synthesis failed: kaboom$")
  expect_identical(notifications[[1]]$type, "error")
  stale <- shiny::isolate(state$stale)
  expect_null(shiny::isolate(state$synthetic))
  expect_null(shiny::isolate(state$comparison))
  expect_null(shiny::isolate(state$privacy))
  expect_true(isTRUE(stale$synthesis))
  expect_true(isTRUE(stale$comparison))
  expect_true(isTRUE(stale$export))
})

# ---- seed / try-new-seed / adjust-settings tests ----------------------------

make_stub_bindings <- function() {
  toy_synthetic <- structure(
    data.frame(x = 1:3),
    class = c("dataganger_synthetic", "data.frame")
  )
  toy_comparison <- structure(
    list(numeric = tibble::tibble(), categorical = tibble::tibble()),
    class = "dataganger_comparison"
  )
  toy_privacy <- local({
    p <- tibble::tibble()
    class(p) <- c("dataganger_privacy_check", class(p))
    attr(p, "exact_row_matches") <- 0L
    p
  })

  list(
    synthesize_data  = function(...) toy_synthetic,
    compare_synthetic = function(...) toy_comparison,
    privacy_check    = function(...) toy_privacy
  )
}

test_that("generate stores seed_used when spec seed is NULL", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development")
  )
  stubs <- make_stub_bindings()
  testthat::local_mocked_bindings(
    synthesize_data   = stubs$synthesize_data,
    compare_synthetic = stubs$compare_synthetic,
    privacy_check     = stubs$privacy_check
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  seed <- shiny::isolate(state$seed_used)
  expect_false(is.null(seed))
  expect_true(is.integer(seed) || (is.numeric(seed) && seed == round(seed)))
})

test_that("generate uses spec seed when not NULL", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development", seed = 42L)
  )
  stubs <- make_stub_bindings()
  testthat::local_mocked_bindings(
    synthesize_data   = stubs$synthesize_data,
    compare_synthetic = stubs$compare_synthetic,
    privacy_check     = stubs$privacy_check
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  expect_identical(shiny::isolate(state$seed_used), 42L)
})

test_that("result_summary includes Seed line after generation", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development", seed = 99L)
  )
  stubs <- make_stub_bindings()
  testthat::local_mocked_bindings(
    synthesize_data   = stubs$synthesize_data,
    compare_synthetic = stubs$compare_synthetic,
    privacy_check     = stubs$privacy_check
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
    expect_match(output$result_summary, "Seed: 99")
  })
})

test_that("try_new_seed runs synthesis and stores a new seed_used", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development")
  )
  stubs <- make_stub_bindings()
  testthat::local_mocked_bindings(
    synthesize_data   = stubs$synthesize_data,
    compare_synthetic = stubs$compare_synthetic,
    privacy_check     = stubs$privacy_check
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(try_new_seed = 1L)
    session$flushReact()
  })

  expect_false(is.null(shiny::isolate(state$synthetic)))
  expect_false(is.null(shiny::isolate(state$seed_used)))
})

test_that("adjust_settings sets nav_request to configure", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development")
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(adjust_settings = 1L)
    session$flushReact()
  })

  expect_identical(shiny::isolate(state$nav_request), "configure")
})
