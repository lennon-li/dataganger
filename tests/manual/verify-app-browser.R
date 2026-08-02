# Manual browser confirmation for the Shiny app.
#
# Not run by devtools::test(). This exists because tests/testthat/test-app-css.R
# uses shinytest2::AppDriver, which on some Linux setups cannot navigate to its
# own shiny subprocess ("Chromote: timed out waiting for response to command
# Page.navigate"). A standalone ChromoteSession reaches the same running app
# without trouble, so this script drives one directly and asserts the same
# design-token properties the automated test does.
#
# Usage, from the package root, against an INSTALLED dataganger:
#   R CMD INSTALL . && Rscript tests/manual/verify-app-browser.R

stopifnot(
  requireNamespace("chromote", quietly = TRUE),
  requireNamespace("shiny", quietly = TRUE)
)

port <- 5099L
url <- sprintf("http://127.0.0.1:%d/", port)
app_dir <- system.file("app", package = "dataganger")
if (!nzchar(app_dir)) {
  stop("dataganger is not installed; run R CMD INSTALL . first")
}

server <- callr::r_bg(
  function(dir, port) {
    shiny::runApp(dir, port = port, host = "127.0.0.1", launch.browser = FALSE)
  },
  args = list(dir = app_dir, port = port)
)
on.exit(server$kill(), add = TRUE)

# The app pulls in bslib, DT and the full module tree before it serves.
deadline <- Sys.time() + 90
repeat {
  ok <- tryCatch(
    {
      con <- url(url); on.exit(close(con), add = FALSE); readLines(con, n = 1L)
      TRUE
    },
    error = function(e) FALSE
  )
  if (isTRUE(ok)) break
  if (Sys.time() > deadline) stop("app did not start within 90s")
  Sys.sleep(2)
}

chromote::set_chrome_args(c(
  chromote::default_chrome_args(),
  "--no-sandbox",
  "--disable-dev-shm-usage"
))
b <- chromote::ChromoteSession$new()
on.exit(b$close(), add = TRUE)

invisible(b$Page$navigate(url, timeout_ = 60))
Sys.sleep(8)

evaluate <- function(js) b$Runtime$evaluate(js)$result$value

# --paper-50: #FBFAF6 = rgb(251, 250, 246)
background <- evaluate("getComputedStyle(document.body).backgroundColor")
sheets <- evaluate("document.querySelectorAll('link[rel=stylesheet]').length")
html <- evaluate("document.documentElement.outerHTML")

checks <- c(
  "colors_and_type.css served" = grepl("colors_and_type.css", html, fixed = TRUE),
  "shiny-app.css served" = grepl("shiny-app.css", html, fixed = TRUE),
  "body background matches --paper-50" = identical(background, "rgb(251, 250, 246)"),
  "stylesheets attached" = is.numeric(sheets) && sheets > 0
)

for (nm in names(checks)) {
  cat(sprintf("%-40s %s\n", nm, if (isTRUE(checks[[nm]])) "PASS" else "FAIL"))
}
cat(sprintf("\nbody background = %s\nstylesheet count = %s\n", background, sheets))

if (!all(unlist(checks))) {
  quit(status = 1L)
}
