# Tests for mod_export_ui / mod_export_server
# Uses testServer() - no runApp(), no browser()

export_test_state <- function(purpose = "ai_programming", seed = 1L) {
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

test_that("mod_export_server passes include_original_names=FALSE for safer_external", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state("safer_external")

  shiny::testServer(mod_export_server, args = list(state = state), {
    session$setInputs(format = "csv", include_report = FALSE, fail_on_exact = FALSE)
    session$flushReact()

    expect_match(output$download, "synthetic_data_seed1\\.csv$")

    rendered_names_ui <- paste(as.character(output$names_ui), collapse = "")
    expect_true(grepl("anonymized", rendered_names_ui, fixed = TRUE))
    expect_false(grepl("include_original_names", rendered_names_ui, fixed = TRUE))
  })
})

test_that("mod_export_server exposes include_original_names=TRUE for ai_programming", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state("ai_programming")

  shiny::testServer(mod_export_server, args = list(state = state), {
    session$flushReact()
    rendered <- paste(as.character(output$names_ui), collapse = "")

    expect_true(grepl("include_original_names", rendered, fixed = TRUE))
    expect_true(grepl("checked=\\\"checked\\\"", rendered))
  })
})

test_that("download filename includes seed from state$seed_used", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state(purpose = "ai_programming", seed = 12345L)

  shiny::testServer(mod_export_server, args = list(state = state), {
    session$setInputs(format = "csv", include_report = FALSE, fail_on_exact = FALSE)
    session$flushReact()
    expect_match(output$download, "synthetic_data_seed12345\\.csv$")
  })
})

test_that("rds download filename also includes seed", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state(purpose = "ai_programming", seed = 7L)

  shiny::testServer(mod_export_server, args = list(state = state), {
    session$setInputs(format = "rds", include_report = FALSE, fail_on_exact = FALSE)
    session$flushReact()
    expect_match(output$download, "synthetic_data_seed7\\.rds$")
  })
})
