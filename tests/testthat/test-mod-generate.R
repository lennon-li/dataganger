# Generation runs in a callr subprocess in production; force the synchronous
# in-process path here so mocked bindings apply and testServer can observe the
# result without driving an async poll loop. Reset after this file.
withr::local_options(dataganger.synthesis_async = FALSE, .local_envir = testthat::teardown_env())

generate_ready_roles <- function(data) {
  roles <- dg_seed_disclosure(detect_roles(data))
  blank <- is.na(roles$identifies) | !nzchar(roles$identifies)
  roles$identifies[blank] <- "none"
  dg_sync_roles_axes(roles)
}

generate_test_state <- function(data = NULL, spec = NULL) {
  shiny::reactiveValues(
    raw_data = data,
    roles = if (!is.null(data)) generate_ready_roles(data) else NULL,
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

test_that("generate UI exposes a configuration recap output", {
  html <- as.character(mod_generate_ui("generate"))
  expect_match(html, "Your configuration")
  expect_match(html, "generate-config_recap")
  expect_match(html, "generate-decision_recap")
})

test_that("generate stale banner uses friendly guidance", {
  html <- as.character(mod_generate_ui("generate"))

  expect_match(
    html,
    "Review the config, press Generate when ready, or go back to adjust settings.",
    fixed = TRUE
  )
  expect_no_match(html, "Results stale", fixed = TRUE)
  expect_no_match(html, "Re-generate before trusting", fixed = TRUE)
})

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

test_that("engine label resolves to the generated engine after synthesis", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development", seed = 99L)
  )
  stubs <- make_stub_bindings()
  stubs$synthesize_data <- function(...) {
    out <- structure(data.frame(x = 1:3), class = c("dataganger_synthetic", "data.frame"))
    attr(out, "engine") <- "internal"
    out
  }
  testthat::local_mocked_bindings(
    synthesize_data   = stubs$synthesize_data,
    compare_synthetic = stubs$compare_synthetic,
    privacy_check     = stubs$privacy_check
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
    recap_html <- paste(as.character(output$config_recap), collapse = "\n")
    expect_match(recap_html, "internal \\(auto\\)")
  })
})

test_that("regenerate is disabled before generation and enabled after", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development", seed = 5L)
  )
  stubs <- make_stub_bindings()
  testthat::local_mocked_bindings(
    synthesize_data   = stubs$synthesize_data,
    compare_synthetic = stubs$compare_synthetic,
    privacy_check     = stubs$privacy_check
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    before_html <- paste(as.character(output$generate_actions), collapse = "\n")
    expect_match(before_html, "Regenerate")
    expect_match(before_html, "disabled")

    session$setInputs(generate = 1L)
    session$flushReact()

    after_html <- paste(as.character(output$generate_actions), collapse = "\n")
    expect_match(after_html, "Regenerate")
    expect_no_match(after_html, "disabled")
  })
})

test_that("result stats include exact row matches after generation", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(x = 1:3),
    spec = synth_spec(purpose = "development", seed = 11L)
  )
  stubs <- make_stub_bindings()
  stubs$privacy_check <- local({
    p <- tibble::tibble()
    class(p) <- c("dataganger_privacy_check", class(p))
    attr(p, "exact_row_matches") <- 2L
    function(...) p
  })
  testthat::local_mocked_bindings(
    synthesize_data   = stubs$synthesize_data,
    compare_synthetic = stubs$compare_synthetic,
    privacy_check     = stubs$privacy_check
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
    stats_html <- paste(as.character(output$result_stats), collapse = "\n")
    expect_match(stats_html, "EXACT MATCHES")
    expect_match(stats_html, ">2<")
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
    session$setInputs(generate = 1L)
    session$flushReact()
    first_seed <- state$seed_used

    session$setInputs(try_new_seed = 1L)
    session$flushReact()

    expect_false(is.null(first_seed))
    expect_false(identical(state$seed_used, first_seed))
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


test_that("decision recap renders the revised review columns", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(name = "a", zip = "100", bp = 10, stringsAsFactors = FALSE),
    spec = synth_spec(purpose = "development")
  )
  state$roles <- tibble::tibble(
    variable = c("name", "zip", "bp"),
    recommended_role = c("ID candidate", "categorical candidate", "numeric"),
    user_role = c(NA_character_, "date", NA_character_),
    class = c("ID candidate", "categorical candidate", "numeric"),
    identifies = c("direct", "combination", "none"),
    sensitive = c(FALSE, TRUE, FALSE),
    simulation = c("drop", "pass_through", "synthesize")
  )

  shiny::testServer(mod_generate_server, args = list(state = state), {
    html <- paste(as.character(output$decision_recap), collapse = "\n")
    expect_match(html, ">Column<")
    expect_match(html, ">Points to a person\\?<")
    expect_match(html, ">Sensitive\\?<")
    expect_match(html, ">Action<")
    expect_match(html, ">What we.ll do<")
    expect_false(grepl("<th[^>]*>TYPE<", html, perl = TRUE))
    expect_false(grepl("<th[^>]*>DISCLOSURE<", html, perl = TRUE))
    expect_match(html, 'title="Modelled as: date"')
    expect_match(html, "Only in combination with other columns")
    expect_match(html, "Pass through")
    expect_match(html, "Use .* Adjust settings to change any of these")
  })
})


test_that("generate blocks when column privacy questions are incomplete", {
  testthat::skip_if_not_installed("shiny")

  state <- generate_test_state(
    data = data.frame(id = c("P1", "P2"), zip = c("100", "200"), stringsAsFactors = FALSE),
    spec = synth_spec(purpose = "development", seed = 1L)
  )
  shiny::isolate({
    roles <- state$roles
    roles$identifies[roles$variable == "zip"] <- ""
    state$roles <- dg_sync_roles_axes(roles)
  })

  recorder <- capture_notifications()
  withr::local_options(recorder$options)

  shiny::testServer(mod_generate_server, args = list(state = state), {
    session$setInputs(generate = 1L)
    session$flushReact()
  })

  notifications <- recorder$get()
  expect_length(notifications, 1)
  expect_match(notifications[[1]]$ui, "Finish the column privacy questions")
  expect_null(shiny::isolate(state$synthetic))
})
