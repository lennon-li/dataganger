compare_test_state <- function(raw_data = NULL, synthetic = NULL,
                               comparison = NULL, privacy = NULL,
                               roles = NULL, stale = NULL) {
  shiny::reactiveValues(
    raw_data   = raw_data,
    synthetic  = synthetic,
    comparison = comparison,
    privacy    = privacy,
    roles      = roles,
    stale      = stale %||% list(comparison = FALSE),
    nav_request = NULL
  )
}

comparison_fixture <- function(seed = 1) {
  data("example_health_survey", package = "dataganger")

  spec <- synth_spec(purpose = "development", seed = seed)
  synthetic <- synthesize_data(example_health_survey, spec)
  roles <- detect_roles(example_health_survey)
  comparison <- compare_synthetic(
    example_health_survey,
    synthetic,
    roles = roles
  )
  privacy <- privacy_check(
    example_health_survey,
    synthetic,
    roles = roles,
    stage = "post",
    spec = spec
  )

  list(
    raw_data   = example_health_survey,
    synthetic  = synthetic,
    comparison = comparison,
    privacy    = privacy,
    roles      = roles
  )
}

test_that("mod_compare_ui has header, subtitle, export button, and stale banner", {
  testthat::skip_if_not_installed("shiny")

  ui   <- mod_compare_ui("compare")
  html <- paste(as.character(ui), collapse = "\n")

  expect_match(html, "Compare datasets")
  expect_match(html, "Step 06")
  expect_match(html, "go_export")
  expect_match(html, "stale__comparison")
})

test_that("compare_body renders empty-state card when no synthetic data", {
  testthat::skip_if_not_installed("shiny")

  state <- compare_test_state()

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$flushReact()
    body_html <- paste(as.character(output$compare_body), collapse = "\n")
    expect_match(body_html, "Generate synthetic data first")
  })
})

test_that("compare_body renders var-rail and var-detail when data is present", {
  testthat::skip_if_not_installed("shiny")

  fixture <- comparison_fixture(seed = 7)
  state   <- compare_test_state(
    raw_data  = fixture$raw_data,
    synthetic = fixture$synthetic,
    roles     = fixture$roles
  )

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$flushReact()
    body_html <- paste(as.character(output$compare_body), collapse = "\n")
    expect_match(body_html, "compare-layout")
    expect_match(body_html, "var-rail")
    expect_match(body_html, "var-detail")
  })
})

test_that("compare_body excludes identifier variables from navigation", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("plotly")

  raw <- data.frame(
    record_id = sprintf("ID%03d", 1:30),
    age = 1:30,
    group = rep(c("a", "b"), 15),
    stringsAsFactors = FALSE
  )
  synthetic <- raw
  synthetic$age <- rev(synthetic$age)
  roles <- detect_roles(raw)
  roles$user_role[roles$variable == "record_id"] <- "identifier"
  roles$user_role[roles$variable == "age"] <- "numeric"

  state <- compare_test_state(
    raw_data = raw,
    synthetic = synthetic,
    roles = roles
  )

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$flushReact()
    body_html <- paste(as.character(output$compare_body), collapse = "\n")
    expect_no_match(body_html, "record_id")
    expect_match(body_html, "age")
    expect_match(body_html, "group")
  })
})

test_that("go_export sets nav_request to export", {
  testthat::skip_if_not_installed("shiny")

  state <- shiny::reactiveValues(
    raw_data    = NULL,
    synthetic   = NULL,
    comparison  = NULL,
    privacy     = NULL,
    roles       = NULL,
    stale       = list(comparison = FALSE),
    nav_request = NULL
  )

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$setInputs(go_export = 1L)
    session$flushReact()
  })

  expect_identical(shiny::isolate(state$nav_request), "export")
})

test_that("categorical comparison treats NA as an explicit missing level", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("plotly")

  raw <- data.frame(group = c("a", NA, NA), stringsAsFactors = FALSE)
  synthetic <- data.frame(group = c("a", "b", NA), stringsAsFactors = FALSE)
  roles <- detect_roles(raw)
  roles$user_role[roles$variable == "group"] <- "categorical"

  state <- compare_test_state(raw_data = raw, synthetic = synthetic, roles = roles)

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$flushReact()
    stats_html <- paste(as.character(output$var_stats), collapse = "\n")
    expect_match(stats_html, "TVD =")
    expect_no_match(stats_html, "NaN")
  })
})

test_that("date comparison handles all-missing dates without Inf summaries", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("plotly")

  raw <- data.frame(visit_date = as.Date(c(NA, NA, NA)))
  synthetic <- data.frame(visit_date = as.Date(c(NA, NA, NA)))
  roles <- detect_roles(raw)
  roles$user_role[roles$variable == "visit_date"] <- "date"

  state <- compare_test_state(raw_data = raw, synthetic = synthetic, roles = roles)

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$flushReact()
    stats_html <- paste(as.character(output$var_stats), collapse = "\n")
    expect_match(stats_html, "\\(Missing\\)")
    expect_no_match(stats_html, "Inf")
    expect_no_match(stats_html, "NaN")
  })
})
