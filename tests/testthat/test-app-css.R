# tests/testthat/test-app-css.R

skip_if_not_installed("shinytest2")
skip_if_not_installed("chromote")

library(shinytest2)

test_that("design system CSS loads and tokens are applied", {
  testthat::skip_if(
    dataganger:::synthesis_dev_loaded(),
    "shinytest2 subprocess requires an installed package; skipping under devtools::load_all()"
  )
  app <- AppDriver$new(
    system.file("app", package = "dataganger"),
    name = "css-check",
    height = 800,
    width = 1200,
    load_timeout = 15000
  )
  on.exit(app$stop())

  # 1. CSS files served — check network resources loaded
  html <- app$get_html("html")
  expect_true(grepl("www/colors_and_type.css", html),
              label = "colors_and_type.css link tag present in HTML")
  expect_true(grepl("www/shiny-app.css", html),
              label = "shiny-app.css link tag present in HTML")

  # 2. Background token applied — body or #app background should be warm off-white
  bg <- app$get_js(
    "getComputedStyle(document.body).backgroundColor"
  )
  # --paper-50: #FBFAF6 = rgb(251, 250, 246)
  expect_equal(bg, "rgb(251, 250, 246)",
               label = "body background matches --paper-50 token")

  # 3. Body font is Inter
  font <- app$get_js(
    "getComputedStyle(document.body).fontFamily"
  )
  expect_true(grepl("Inter", font, ignore.case = TRUE),
              label = "body font includes Inter")
})
