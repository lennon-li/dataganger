roles_upload_fixture_path <- function(data, filename) {
  path <- tempfile(pattern = tools::file_path_sans_ext(filename))
  path <- paste0(path, ".", tools::file_ext(filename))
  readr::write_csv(data, path)
  path
}

roles_load_example_data <- function(name) {
  data_env <- new.env(parent = emptyenv())
  utils::data(list = name, package = "dataganger", envir = data_env)
  data_env[[name]]
}

roles_upload_input_value <- function(path, type = "text/csv") {
  data.frame(
    name = basename(path),
    size = file.info(path)$size,
    type = type,
    datapath = path,
    stringsAsFactors = FALSE
  )
}

roles_host_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    state <- mod_state_server("state")
    mod_upload_server("upload", state)
    mod_roles_server("roles", state)

    shiny::observe({
      if (!is.null(state$raw_data) &&
          !is.null(state$profile) &&
          is.null(state$roles)) {
        state$roles <- detect_roles(state$raw_data, profile = state$profile)
      }
    })

    list(state = state)
  })
}

test_that("editing user_role and confirming writes back to state", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    expect_s3_class(state$roles, "dataganger_roles")

    session$setInputs(
      `roles-role_change` = list(row = 1L, value = "numeric")
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_equal(state$roles$user_role[[1]], "numeric")
  })
})

test_that("editing Action treatment and confirming writes back to state", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-simulation-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    expect_equal(state$roles$simulation[[1]], "synthesize")

    session$setInputs(
      `roles-simulation_change` = list(row = 1L, value = "pass_through")
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_equal(state$roles$simulation[[1]], "pass_through")
  })
})

test_that("invalid simulation treatment is ignored silently", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-simulation-invalid-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    original_simulation <- state$roles$simulation
    session$setInputs(
      `roles-simulation_change` = list(row = 1L, value = "explode")
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_identical(state$roles$simulation, original_simulation)
  })
})

test_that("confirming role edits invalidates downstream state", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-stale-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    state$spec <- list(purpose = "development")
    state$synthetic <- tibble::tibble(x = 1)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    session$flushReact()

    session$setInputs(
      `roles-role_change` = list(row = 1L, value = "identifier")
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_true(isTRUE(state$stale$synthesis))
    expect_null(state$spec)
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
  })
})

test_that("editing a non-user_role column is ignored silently", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-readonly-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    original_user_roles <- state$roles$user_role

    # Invalid role value is silently rejected
    session$setInputs(
      `roles-role_change` = list(row = 1L, value = "hacked_role")
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_identical(state$roles$user_role, original_user_roles)
  })
})


test_that("roles table labels the Action and TYPE columns", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-type-header.csv"
  )

  shiny::testServer(roles_host_server, {
    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    html <- paste(as.character(output$`roles-roles_table`), collapse = "
")
    expect_match(html, ">Action<")
    expect_false(grepl(">Simulation<", html))
    expect_match(html, ">TYPE<")
    expect_false(grepl(">user_role<", html))
  })
})

test_that("disclosure gate excludes drop and pass-through rows from unset count", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    roles <- tibble::tibble(
      variable = c("drop_me", "share_me", "needs_role"),
      class = c("character", "numeric", "numeric"),
      recommended_role = c("free text", "numeric", "numeric"),
      user_role = c(NA_character_, NA_character_, NA_character_),
      simulation = c("drop", "pass_through", "synthesize"),
      reason = c("reason", "reason", "reason"),
      disclosure_role = c(NA_character_, NA_character_, NA_character_),
      disclosure_reason = c(NA_character_, NA_character_, NA_character_)
    )
    class(roles) <- c("dataganger_roles", class(roles))

    state$roles <- roles
    session$flushReact()

    html <- paste(as.character(output$`roles-disclosure_gate`), collapse = "\n")
    expect_match(html, "1 column still need a disclosure role")
    expect_false(grepl("3 columns", html, fixed = TRUE))
  })
})


test_that("agg_warning banner shows for aggregated count tables", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  agg <- data.frame(
    region = rep(c("North", "South", "East", "West"), each = 2L),
    sex    = rep(c("F", "M"), times = 4L),
    n      = c(12L, 9L, 7L, 4L, 15L, 11L, 6L, 3L),
    stringsAsFactors = FALSE
  )
  csv_path <- roles_upload_fixture_path(agg, "roles-aggregated.csv")

  shiny::testServer(roles_host_server, {
    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    html <- paste(as.character(output$`roles-agg_warning`), collapse = "\n")
    expect_match(html, "aggregated data")
  })
})

test_that("agg_warning banner stays empty for individual-level microdata", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey,
    "roles-microdata.csv"
  )

  shiny::testServer(roles_host_server, {
    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    html <- paste(as.character(output$`roles-agg_warning`), collapse = "\n")
    expect_false(grepl("aggregated data", html))
  })
})
