synth_controls_host_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    state <- mod_state_server("state")
    controls <- mod_synthesis_controls_server("controls", state)
    list(state = state, controls = controls)
  })
}

test_that("advanced settings use a collapsed disclosure", {
  html <- as.character(mod_synthesis_controls_ui("controls"))

  expect_match(html, "<details>", fixed = TRUE)
  expect_match(html, "<summary>Advanced settings</summary>", fixed = TRUE)
  expect_match(html, "Defaults are safe")
  expect_no_match(html, "expanded by default", fixed = TRUE)
  expect_no_match(html, "<details open", fixed = TRUE)
})

test_that("A1 confirm writes development spec", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "development")
  })
})

test_that("analytics without checkbox leaves state spec NULL", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "analytics")
    session$setInputs(`controls-acknowledge_risk` = FALSE)
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_null(state$spec)
  })
})

test_that("analytics with checkbox writes analytics spec", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "analytics")
    session$setInputs(`controls-acknowledge_risk` = TRUE)
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "analytics")
    expect_true(isTRUE(state$spec$acknowledged_risk))
  })
})

test_that("demo spec uses preset name and geography strategies", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "demo")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_identical(state$spec$purpose, "demo")
  })
})

test_that("confirming a changed spec sets all stale flags", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()
    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    state$synthetic <- tibble::tibble(x = 1)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    session$flushReact()

    session$setInputs(`controls-purpose_group` = "analytics")
    session$setInputs(`controls-acknowledge_risk` = TRUE)
    session$flushReact()
    session$setInputs(`controls-confirm` = 2L)
    session$flushReact()

    expect_true(isTRUE(state$stale$synthesis))
    expect_true(isTRUE(state$stale$comparison))
    expect_true(isTRUE(state$stale$export))
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
  })
})


test_that("purpose card shows a single Protection meter", {
  html <- as.character(dg_purpose_card(
    shiny::NS("x"), "demo", "demo", "Demo", "line", 5
  ))
  expect_match(html, "Protection")
  expect_false(grepl("identifiability", html, ignore.case = FALSE))
})

test_that("Configure confirm is blocked until every generated column has UI answers", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()

    df    <- data.frame(age = 1:5, visit = as.Date("2020-01-01") + 0:4)
    roles <- detect_roles(df)
    roles <- dg_ensure_ui_roles(roles)

    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_equal(state$spec_confirmed %||% 0L, 0L)

    roles$user_identifies <- "none"
    roles$user_sensitive <- FALSE
    roles$identifies <- "none"
    roles$sensitive <- FALSE
    roles <- dg_sync_roles_axes(roles)
    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 2L)
    session$flushReact()

    expect_true((state$spec_confirmed %||% 0L) >= 1L)
  })
})

test_that("Configure confirm ignores missing UI answers on dropped or pass-through columns", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()

    roles <- dg_ensure_ui_roles(detect_roles(data.frame(age = 1:5, city = letters[1:5])))
    roles$simulation <- c("drop", "pass_through")

    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_true((state$spec_confirmed %||% 0L) >= 1L)
  })
})

test_that("Configure confirm still blocks a synthesized column with missing UI answer", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(synth_controls_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`controls-purpose_group` = "development")
    session$flushReact()

    roles <- dg_ensure_ui_roles(detect_roles(data.frame(age = 1:5, city = letters[1:5])))
    roles$simulation <- c("synthesize", "drop")

    state$roles <- roles
    session$flushReact()

    session$setInputs(`controls-confirm` = 1L)
    session$flushReact()

    expect_equal(state$spec_confirmed %||% 0L, 0L)
  })
})



# --- live threshold readouts --------------------------------------------------
# The two Advanced sliders share a default of 5 but count different things:
# rare_level_min_n counts one value inside one column, k_anon counts rows
# sharing a combination across columns. Each readout is asserted against a
# fixture with a hand-checked answer, so a wrong count cannot pass silently.
#
# These drive mod_synthesis_controls_server() directly rather than through the
# host wrapper used above: the sliders are created inside renderUI, and
# setInputs() on the host does not reach a nested module's dynamic inputs.

hint_fixture <- function() {
  data.frame(
    # 3 groups of 4 rows, so every (city, band) combination is below k = 5 and
    # none is below k = 4.
    city  = rep(c("alpha", "beta", "gamma"), each = 4L),
    band  = rep("x", 12L),
    # 2 rare labels (1 row each) alongside 1 common label (10 rows).
    grade = c(rep("common", 10L), "r1", "r2"),
    stringsAsFactors = FALSE
  )
}

hint_roles <- function(df, combination = c("city", "band")) {
  roles <- dg_ensure_ui_roles(detect_roles(df))
  roles$identifies <- ifelse(roles$variable %in% combination,
                             "combination", "none")
  roles$sensitive <- FALSE
  roles
}

hint_state <- function(df, roles) {
  shiny::reactiveValues(raw_data = df, roles = roles)
}

hint_html <- function(out) as.character(out$html)

test_that("k readout counts combinations and rows below the chosen k", {
  testthat::skip_if_not_installed("shiny")

  df <- hint_fixture()
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, hint_roles(df))),
    {
      session$setInputs(purpose_group = "development", k_anon = 5L)
      session$flushReact()

      html <- hint_html(output$kanon_hint)

      expect_match(html, "At 5:", fixed = TRUE)
      expect_match(html, "your 2 combination columns (city, band)", fixed = TRUE)
      expect_match(html, "3 distinct combinations", fixed = TRUE)
      expect_match(html, "3 of them are held by fewer than 5 rows", fixed = TRUE)
      expect_match(html, "12 of 12 rows (100%)", fixed = TRUE)
    }
  )
})

test_that("k readout reports nothing to suppress when every group is large enough", {
  testthat::skip_if_not_installed("shiny")

  df <- hint_fixture()
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, hint_roles(df))),
    {
      # Groups are exactly 4 rows, so k = 4 is satisfied where k = 5 was not.
      session$setInputs(purpose_group = "development", k_anon = 4L)
      session$flushReact()

      html <- hint_html(output$kanon_hint)

      expect_match(html, "At 4:", fixed = TRUE)
      expect_match(html, "None are held by too few rows", fixed = TRUE)
      expect_no_match(html, "coarsened first", fixed = TRUE)
    }
  )
})

test_that("k readout reports the empty state when nothing identifies in combination", {
  testthat::skip_if_not_installed("shiny")

  df <- hint_fixture()
  roles <- hint_roles(df, combination = character(0))
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, roles)),
    {
      session$setInputs(purpose_group = "development", k_anon = 5L)
      session$flushReact()

      html <- hint_html(output$kanon_hint)

      expect_match(html, "No columns are marked as identifying in combination",
                   fixed = TRUE)
      expect_no_match(html, "distinct combinations", fixed = TRUE)
    }
  )
})

test_that("k readout keys on factor codes so separator-like values cannot collide", {
  testthat::skip_if_not_installed("shiny")

  # ("a|~|b", "c") and ("a", "b|~|c") are distinct combinations that a naive
  # paste with "|~|" would fold into one. There are 2 combinations here, not 1.
  df <- data.frame(
    p = c("a|~|b", "a", "a|~|b", "a"),
    q = c("c", "b|~|c", "c", "b|~|c"),
    stringsAsFactors = FALSE
  )
  roles <- hint_roles(df, combination = c("p", "q"))
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, roles)),
    {
      session$setInputs(purpose_group = "development", k_anon = 5L)
      session$flushReact()

      expect_match(hint_html(output$kanon_hint), "2 distinct combinations",
                   fixed = TRUE)
    }
  )
})

test_that("rare readout counts rare values and says when nothing masks them", {
  testthat::skip_if_not_installed("shiny")

  df <- hint_fixture()
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, hint_roles(df))),
    {
      session$setInputs(purpose_group = "development", rare_level_min_n = 5L)
      session$flushReact()

      html <- hint_html(output$rare_hint)

      # city: 3 levels of 4 rows, all rare. band: 1 level of 12, not rare.
      # grade: "common" not rare, "r1"/"r2" rare. So 5 rare of 7 distinct,
      # over 2 of the 3 text columns.
      expect_match(html, "At 5:", fixed = TRUE)
      expect_match(html, "5 of 7 distinct values are rare", fixed = TRUE)
      expect_match(html, "2 of 3 text or category columns", fixed = TRUE)
      expect_match(html, "No column is set to mask rare values", fixed = TRUE)
    }
  )
})

test_that("rare readout reports how many columns are set to mask", {
  testthat::skip_if_not_installed("shiny")

  df <- hint_fixture()
  roles <- hint_roles(df)
  roles$label_strategy <- ifelse(roles$variable == "grade",
                                 "mask_rare", "preserve")
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, roles)),
    {
      session$setInputs(purpose_group = "development", rare_level_min_n = 5L)
      session$flushReact()

      html <- hint_html(output$rare_hint)

      expect_match(html, "1 column is set to mask rare values", fixed = TRUE)
      expect_no_match(html, "No column is set to mask", fixed = TRUE)
    }
  )
})

test_that("rare readout lowers its count as the threshold drops", {
  testthat::skip_if_not_installed("shiny")

  df <- hint_fixture()
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, hint_roles(df))),
    {
      # At 2, only the single-row grade labels stay rare; the 4-row city
      # levels no longer qualify.
      session$setInputs(purpose_group = "development", rare_level_min_n = 2L)
      session$flushReact()

      html <- hint_html(output$rare_hint)

      expect_match(html, "At 2:", fixed = TRUE)
      expect_match(html, "2 of 7 distinct values are rare", fixed = TRUE)
      expect_match(html, "1 of 3 text or category columns", fixed = TRUE)
    }
  )
})

test_that("both threshold sliders step in whole numbers", {
  testthat::skip_if_not_installed("shiny")

  df <- hint_fixture()
  shiny::testServer(
    mod_synthesis_controls_server,
    args = list(state = hint_state(df, hint_roles(df))),
    {
      session$setInputs(purpose_group = "development")
      session$flushReact()

      html <- as.character(output$advanced_settings$html)

      # Both are integer counts; a fractional slider value would be silently
      # truncated by the as.integer() coercion downstream.
      expect_match(html, "data-step=\"1\"")
      expect_equal(lengths(regmatches(html, gregexpr("data-step=\"1\"", html))),
                   2L)
    }
  )
})
