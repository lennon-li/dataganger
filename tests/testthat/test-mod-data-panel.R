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
