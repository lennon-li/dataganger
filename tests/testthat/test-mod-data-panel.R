test_that("data panel compare mode renders a compare table output", {
  testthat::skip_if_not_installed("shiny")

  state <- shiny::reactiveValues(
    raw_data = data.frame(a = 1:3),
    synthetic = data.frame(a = 3:1),
    compare_selected_var = "a",
    active_step = "compare",
    seed_used = 1L
  )

  shiny::testServer(mod_data_panel_server, args = list(state = state), {
    session$flushReact()
    body_html <- paste(as.character(output$dp_body), collapse = "\n")
    expect_match(body_html, "dp_compare_table")
    expect_match(body_html, "Row-by-row")
  })
})

test_that("data panel flags exact-match rows for highlighting on both tabs", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  # 30 rows meets the >= 20 threshold; inject two verbatim copies at 3 and 7.
  original <- data.frame(
    a = sprintf("%02d", 1:30), b = rep(c("x", "y"), 15), stringsAsFactors = FALSE
  )
  synthetic <- data.frame(
    a = sprintf("%02d", 31:60), b = rep(c("y", "x"), 15), stringsAsFactors = FALSE
  )
  synthetic[c(3, 7), ] <- original[c(3, 7), ]

  state <- shiny::reactiveValues(
    raw_data = original, synthetic = synthetic, roles = NULL,
    compare_selected_var = NULL, active_step = "generate", seed_used = 1L
  )

  shiny::testServer(mod_data_panel_server, args = list(state = state), {
    session$flushReact()

    fl <- exact_match_flags()
    expect_false(is.null(fl))
    expect_equal(sum(fl$synthetic), 2L)
    expect_true(all(fl$synthetic[c(3, 7)]))
    expect_equal(sum(fl$original), 2L)
    expect_true(all(fl$original[c(3, 7)]))

    # The table renders without error on both tabs (hidden flag column + row
    # style must not break DT).
    session$setInputs(active_tab = "synth")
    session$flushReact()
    expect_false(is.null(output$dp_table))

    session$setInputs(active_tab = "real")
    session$flushReact()
    expect_false(is.null(output$dp_table))
  })
})

test_that("data panel has no exact-match flags before synthesis", {
  testthat::skip_if_not_installed("shiny")

  state <- shiny::reactiveValues(
    raw_data = data.frame(a = sprintf("%02d", 1:30)), synthetic = NULL,
    roles = NULL, compare_selected_var = NULL, active_step = "configure",
    seed_used = NULL
  )

  shiny::testServer(mod_data_panel_server, args = list(state = state), {
    session$flushReact()
    expect_null(exact_match_flags())
  })
})

test_that("each new synthetic result switches the data panel to Synthetic", {
  testthat::skip_if_not_installed("shiny")

  state <- shiny::reactiveValues(
    raw_data = data.frame(a = 1:3),
    synthetic = NULL,
    compare_selected_var = NULL,
    active_step = "generate",
    seed_used = 1L,
    roles = NULL
  )

  shiny::testServer(mod_data_panel_server, args = list(state = state), {
    session$flushReact()

    state$synthetic <- data.frame(a = 3:1)
    session$flushReact()
    expect_match(paste(as.character(output$dp_body), collapse = "\n"), "seed = 1")

    session$setInputs(active_tab = "real")
    session$flushReact()
    expect_match(paste(as.character(output$dp_body), collapse = "\n"), "source dataset")

    state$seed_used <- 2L
    state$synthetic <- data.frame(a = 4:2)
    session$flushReact()
    expect_match(paste(as.character(output$dp_body), collapse = "\n"), "seed = 2")
  })
})
