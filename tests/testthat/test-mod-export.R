# Tests for mod_export_ui / mod_export_server (single-bundle design)
# Uses testServer() - no runApp(), no browser()

export_test_state <- function(purpose = "development", seed = 1L) {
  toy_data <- data.frame(secret_col = 1:3, val = c("x", "y", "z"))

  shiny::reactiveValues(
    synthetic = toy_data,
    raw_data = toy_data,
    roles = NULL,
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

test_that("export summary shows synthesis, pass-through, and drop counts", {
  testthat::skip_if_not_installed("shiny")

  raw_data <- data.frame(
    synth_col = 1:4,
    shared_col = letters[1:4],
    drop_col = c("x", "y", "z", "w"),
    stringsAsFactors = FALSE
  )
  synthetic <- raw_data[c("synth_col", "shared_col")]
  roles <- data.frame(
    variable = c("synth_col", "shared_col", "drop_col"),
    simulation = c("synthesize", "pass_through", "drop"),
    stringsAsFactors = FALSE
  )

  state <- export_test_state()
  state$raw_data <- raw_data
  state$synthetic <- synthetic
  state$roles <- roles

  shiny::testServer(mod_export_server, args = list(state = state), {
    summary_html <- paste(as.character(output$export_summary), collapse = "\n")
    expect_match(summary_html, "Original")
    expect_match(summary_html, "4 rows \u00d7 3 cols")
    expect_match(summary_html, "Synthesized")
    expect_match(summary_html, "Pass-through")
    expect_match(summary_html, "Dropped")
    expect_match(summary_html, "1 column")
    expect_match(summary_html, "Final synthetic")
    expect_match(summary_html, "4 rows \u00d7 2 cols")
  })
})

test_that("export summary counts role-excluded columns (e.g. IDs) as dropped", {
  testthat::skip_if_not_installed("shiny")

  # A column absent from the synthetic with NO Action = drop (e.g. an ID
  # excluded by detect_roles) must still reconcile as dropped.
  raw_data <- data.frame(
    id = 1:4,
    age = c(20L, 30L, 40L, 50L),
    sex = c("F", "M", "F", "M"),
    stringsAsFactors = FALSE
  )
  synthetic <- raw_data[c("age", "sex")]
  roles <- data.frame(
    variable = c("id", "age", "sex"),
    simulation = c("synthesize", "synthesize", "synthesize"),
    stringsAsFactors = FALSE
  )

  state <- export_test_state()
  state$raw_data <- raw_data
  state$synthetic <- synthetic
  state$roles <- roles

  shiny::testServer(mod_export_server, args = list(state = state), {
    summary_html <- paste(as.character(output$export_summary), collapse = "\n")
    expect_match(summary_html, "4 rows \u00d7 3 cols")   # original
    expect_match(summary_html, "4 rows \u00d7 2 cols")   # final
    # 2 synthesized, 0 pass-through, 1 dropped (the id) -> ties out to 3
    expect_match(summary_html, "Dropped")
    expect_match(summary_html, "1 column")
  })
})
