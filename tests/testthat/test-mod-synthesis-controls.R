synth_controls_host_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    state <- mod_state_server("state")
    controls <- mod_synthesis_controls_server("controls", state)
    list(state = state, controls = controls)
  })
}

test_that("A1 confirm writes ai_programming spec", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "prototype")
    session$setInputs(`controls-prototype_choice` = "ai_programming")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "ai_programming")
  })
})

test_that("internal_hifi without checkbox leaves state spec NULL", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "internal_hifi")
    session$setInputs(`controls-acknowledge_risk` = FALSE)
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_null(state$spec)
  })
})

test_that("internal_hifi with checkbox writes internal_hifi spec", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "internal_hifi")
    session$setInputs(`controls-acknowledge_risk` = TRUE)
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "internal_hifi")
    expect_true(isTRUE(state$spec$acknowledged_risk))
  })
})

test_that("safer_external spec fixes name and geography strategies", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "safer_external")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$name_strategy, "generic")
    expect_identical(state$spec$geography_strategy, "aggregate")
  })
})

test_that("confirming a changed spec sets all stale flags", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "prototype")
    session$setInputs(`controls-prototype_choice` = "ai_programming")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    state$synthetic <- tibble::tibble(x = 1)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    session$flushReact()

    expect_warning(
      {
        session$setInputs(`controls-prototype_choice` = "model_prototype")
        session$flushReact()
      },
      "Relationship-aware synthesis is planned for a future release"
    )
    session$setInputs(`controls-confirm` = 2L)
    session$flushReact()

    expect_true(isTRUE(state$stale$synthesis))
    expect_true(isTRUE(state$stale$comparison))
    expect_true(isTRUE(state$stale$export))
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
  })
})
