compare_test_state <- function(raw_data = NULL, synthetic = NULL,
                               comparison = NULL, privacy = NULL) {
  shiny::reactiveValues(
    raw_data = raw_data,
    synthetic = synthetic,
    comparison = comparison,
    privacy = privacy
  )
}

comparison_fixture <- function(seed = 1) {
  data("example_health_survey", package = "dataganger")

  spec <- synth_spec(purpose = "ai_programming", seed = seed)
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
    raw_data = example_health_survey,
    synthetic = synthetic,
    comparison = comparison,
    privacy = privacy
  )
}

test_that("mod_compare_ui exposes all four tabs and stale banner", {
  testthat::skip_if_not_installed("shiny")

  ui <- mod_compare_ui("compare")
  html <- paste(as.character(ui), collapse = "\n")

  expect_match(html, "Dataset")
  expect_match(html, "Numeric")
  expect_match(html, "Categorical")
  expect_match(html, "Privacy")
  expect_match(html, "stale__comparison")
})

test_that("dataset and privacy tabs render expected summaries", {
  testthat::skip_if_not_installed("shiny")

  fixture <- comparison_fixture(seed = 7)
  state <- compare_test_state(
    raw_data = fixture$raw_data,
    synthetic = fixture$synthetic,
    comparison = fixture$comparison,
    privacy = fixture$privacy
  )

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$flushReact()

    dataset_html <- paste(as.character(output$dataset_tab), collapse = "\n")
    privacy_html <- paste(as.character(output$privacy_tab), collapse = "\n")

    expect_match(dataset_html, "Original")
    expect_match(dataset_html, "Synthetic")
    expect_match(
      privacy_html,
      paste0("Exact row matches: ", attr(state$privacy, "exact_row_matches", exact = TRUE))
    )
  })
})

test_that("numeric and categorical tabs fall back cleanly when comparisons are empty", {
  testthat::skip_if_not_installed("shiny")

  comparison <- structure(
    list(
      dataset = tibble::tibble(metric = "nrow", original = 5, synthetic = 5, value = NA_real_),
      numeric = tibble::tibble(),
      categorical = tibble::tibble(),
      relationship = tibble::tibble(),
      privacy_flags = NULL,
      meta = list()
    ),
    class = "dataganger_comparison"
  )
  privacy <- tibble::tibble(
    variable = character(0),
    flag = character(0),
    severity = character(0),
    recommendation = character(0)
  )
  attr(privacy, "exact_row_matches") <- 0L
  class(privacy) <- c("dataganger_privacy_check", class(privacy))

  state <- compare_test_state(
    raw_data = data.frame(group = letters[1:5], stringsAsFactors = FALSE),
    synthetic = data.frame(group = letters[1:5], stringsAsFactors = FALSE),
    comparison = comparison,
    privacy = privacy
  )

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$flushReact()

    expect_match(
      paste(as.character(output$numeric_tab), collapse = "\n"),
      "No numeric comparison available\\."
    )
    expect_match(
      paste(as.character(output$categorical_tab), collapse = "\n"),
      "No categorical comparison available\\."
    )
  })
})

test_that("adjust_settings sets nav_request to purpose", {
  testthat::skip_if_not_installed("shiny")

  state <- shiny::reactiveValues(
    raw_data = NULL,
    synthetic = NULL,
    comparison = NULL,
    privacy = NULL,
    nav_request = NULL
  )

  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$setInputs(adjust_settings = 1L)
    session$flushReact()
  })

  expect_identical(shiny::isolate(state$nav_request), "purpose")
})
