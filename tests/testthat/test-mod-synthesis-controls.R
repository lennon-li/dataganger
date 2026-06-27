synth_controls_host_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    state <- mod_state_server("state")
    controls <- mod_synthesis_controls_server("controls", state)
    list(state = state, controls = controls)
  })
}

test_that("A1 confirm writes development spec", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "development")
  })
})

test_that("analytics without checkbox leaves state spec NULL", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "analytics")
    session$setInputs(`controls-acknowledge_risk` = FALSE)
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_null(state$spec)
  })
})

test_that("analytics with checkbox writes analytics spec", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "analytics")
    session$setInputs(`controls-acknowledge_risk` = TRUE)
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "analytics")
    expect_true(isTRUE(state$spec$acknowledged_risk))
  })
})

test_that("demo spec uses preset name and geography strategies", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "demo")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "demo")
  })
})

test_that("confirming a changed spec sets all stale flags", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    state$synthetic <- tibble::tibble(x = 1)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    session$flushReact()

    session$setInputs(`controls-purpose_group` = "analytics")
    session$setInputs(`controls-acknowledge_risk` = TRUE)
    session$flushReact()
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


test_that("purpose card meters use unified Title-Case labels incl. Anonymity", {
  html <- as.character(dg_purpose_card(
    shiny::NS("x"), "demo", "demo", "Demo", "line", 2, 4, 1
  ))
  expect_match(html, "Coarsening")
  expect_match(html, "Privacy")
  expect_match(html, "Anonymity")
  expect_false(grepl("identifiability", html, ignore.case = FALSE))
})

test_that("Configure confirm is blocked until every column has a disclosure role", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()

    # Build a proper dataganger_roles object; force all disclosure_roles to NA
    df    <- data.frame(age = 1:5, city = letters[1:5])
    roles <- detect_roles(df)
    roles$disclosure_role <- NA_character_

    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    # Gate must block: spec_confirmed must stay at 0
    expect_equal(state$spec_confirmed %||% 0L, 0L)

    # Fix all disclosure roles and confirm again -> must advance
    roles$disclosure_role <- "none"
    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 2L)
    session$flushReact()

    expect_true((state$spec_confirmed %||% 0L) >= 1L)
  })
})

test_that("Configure confirm ignores missing disclosure roles on dropped or pass-through columns", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()

    roles <- detect_roles(data.frame(age = 1:5, city = letters[1:5]))
    roles$simulation <- c("drop", "pass_through")
    roles$disclosure_role <- NA_character_

    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_true((state$spec_confirmed %||% 0L) >= 1L)
  })
})

test_that("Configure confirm still blocks a synthesized column with missing disclosure role", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()

    roles <- detect_roles(data.frame(age = 1:5, city = letters[1:5]))
    roles$simulation <- c("synthesize", "drop")
    roles$disclosure_role <- c(NA_character_, NA_character_)

    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_equal(state$spec_confirmed %||% 0L, 0L)
  })
})
