# Tests for mod_export_ui / mod_export_server (single-bundle design)
# Uses testServer() - no runApp(), no browser()

export_test_state <- function(purpose = "development", seed = 1L) {
  toy_data <- data.frame(secret_col = 1:3, val = c("x", "y", "z"))

  shiny::reactiveValues(
    synthetic = toy_data,
    raw_data = toy_data,
    spec = synth_spec(purpose = purpose, seed = seed),
    comparison = NULL,
    privacy = NULL,
    seed_used = seed,
    nav_request = NULL,
    stale = list(
      synthesis = FALSE,
      comparison = FALSE,
      export = FALSE
    )
  )
}

test_that("download filename is a seeded bundle zip", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state(purpose = "development", seed = 1L)

  shiny::testServer(mod_export_server, args = list(state = state), {
    expect_match(output$download, "synthetic_data_seed1_bundle\\.zip$")
  })
})

test_that("download filename reflects state$seed_used", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state(purpose = "development", seed = 12345L)

  shiny::testServer(mod_export_server, args = list(state = state), {
    expect_match(output$download, "synthetic_data_seed12345_bundle\\.zip$")
  })
})

test_that("use_original_names is FALSE only for the demo purpose", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(mod_export_server, args = list(state = export_test_state("demo")), {
    expect_false(use_original_names())
  })
  shiny::testServer(mod_export_server, args = list(state = export_test_state("development")), {
    expect_true(use_original_names())
  })
})
