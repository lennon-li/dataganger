test_that("column_filter_suggested_drop flags id-like column names only", {
  cols <- c("id", "patient_id", "record_num", "age", "score", "city")
  expect_identical(
    dataganger:::column_filter_suggested_drop(cols),
    c("id", "patient_id", "record_num")
  )
})

test_that("column_filter_suggested_drop returns character(0) when nothing matches", {
  expect_identical(
    dataganger:::column_filter_suggested_drop(c("age", "score", "city")),
    character(0)
  )
})

test_that("column_filter_modal pre-suggests id-like columns into the drop zone", {
  testthat::skip_if_not_installed("shiny")

  html <- as.character(
    dataganger:::column_filter_modal(
      c("patient_id", "age", "city"),
      ns = shiny::NS("column_filter")
    )
  )

  # Zones render in a fixed order (synthesize, pass_through, drop); the text
  # between one zone's data-bucket marker and the next belongs to that zone.
  zone_chunks <- strsplit(html, 'data-bucket="', fixed = TRUE)[[1]][-1]
  bucket_of <- function(col) {
    for (chunk in zone_chunks) {
      if (grepl(sprintf('data-col="%s"', col), chunk, fixed = TRUE)) {
        return(sub('".*', "", chunk))
      }
    }
    NA_character_
  }

  expect_identical(bucket_of("patient_id"), "drop")
  expect_identical(bucket_of("age"), "synthesize")
  expect_identical(bucket_of("city"), "synthesize")
})

column_filter_host_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    state <- mod_state_server("state")
    mod_column_filter_server("column_filter", state)
    list(state = state)
  })
}

test_that("applying the popup's buckets stores them on state$column_filter", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(column_filter_host_server, {
    state <- session$getReturned()$state

    state$raw_data <- tibble::tibble(patient_id = 1:3, age = c(20, 30, 40))
    session$flushReact()

    session$setInputs(
      `column_filter-buckets` = list(patient_id = "drop", age = "synthesize")
    )
    session$flushReact()

    expect_identical(
      state$column_filter,
      list(patient_id = "drop", age = "synthesize")
    )
  })
})

test_that("a fresh upload clears any previously applied column filter", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(column_filter_host_server, {
    state <- session$getReturned()$state

    state$raw_data <- tibble::tibble(patient_id = 1:3, age = c(20, 30, 40))
    session$flushReact()
    session$setInputs(
      `column_filter-buckets` = list(patient_id = "drop", age = "synthesize")
    )
    session$flushReact()
    expect_false(is.null(state$column_filter))

    state$raw_data <- tibble::tibble(city = c("A", "B"))
    session$flushReact()

    expect_null(state$column_filter)
  })
})
