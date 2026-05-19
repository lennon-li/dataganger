generate_test_state <- function(data = NULL, spec = NULL) {
  shiny::reactiveValues(
    raw_data = data,
    spec = spec,
    synthetic = NULL,
    comparison = NULL,
    privacy = NULL,
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

  state <- generate_test_state(spec = synth_spec(purpose = "ai_programming"))
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
  spec <- synth_spec(purpose = "ai_programming", seed = 1)
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
  spec <- synth_spec(purpose = "ai_programming", seed = 2)
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
  spec <- synth_spec(purpose = "ai_programming", seed = 3)
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
