# Tests for mod_export_ui / mod_export_server
# Uses testServer() - no runApp(), no browser()

export_test_state <- function(purpose = "ai_programming") {
  toy_data <- data.frame(secret_col = 1:3, val = c("x", "y", "z"))

  shiny::reactiveValues(
    synthetic = toy_data,
    raw_data = toy_data,
    spec = synth_spec(purpose = purpose, seed = 1),
    comparison = NULL,
    privacy = NULL,
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
  called_args <- NULL

  testthat::local_mocked_bindings(
    export_synthetic = function(...) {
      called_args <<- list(...)
      invisible(NULL)
    }
  )

  shiny::testServer(mod_export_server, args = list(state = state), {
    session$setInputs(format = "rds", include_report = FALSE, fail_on_exact = FALSE)
    session$flushReact()
    output$download
  })

  expect_false(isTRUE(called_args$include_original_names))
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
