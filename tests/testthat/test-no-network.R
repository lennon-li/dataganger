local_no_network_traps <- function() {
  # testthat's mocked bindings do not reliably bind these base/namespace
  # functions in this setup, so trap them directly at the namespace level.
  boom <- quote(stop("network access attempted", call. = FALSE))

  trace("url", tracer = boom, where = asNamespace("base"), print = FALSE)
  trace("socketConnection", tracer = boom, where = asNamespace("base"), print = FALSE)
  trace("download.file", tracer = boom, where = asNamespace("utils"), print = FALSE)

  withr::defer(untrace("url", where = asNamespace("base")))
  withr::defer(untrace("socketConnection", where = asNamespace("base")))
  withr::defer(untrace("download.file", where = asNamespace("utils")))

  invisible(NULL)
}

test_that("the full pipeline and app UI construction make no network calls", {
  local_no_network_traps()

  df <- data.frame(
    age = sample(20:80, 40, replace = TRUE),
    grp = sample(c("a", "b"), 40, replace = TRUE),
    stringsAsFactors = FALSE
  )
  roles <- dg_sync_roles_axes(detect_roles(df))
  spec <- synth_spec("development", seed = 1L, engine = "internal")
  syn <- synthesize_data(df, spec, roles = roles)

  expect_s3_class(compare_synthetic(df, syn, roles = roles), "dataganger_comparison")

  out_dir <- file.path(withr::local_tempdir(), "bundle")
  expect_no_error(suppressWarnings(
    export_synthetic(
      syn,
      original = df,
      roles = roles,
      path = out_dir,
      format = "dir",
      include_report = FALSE
    )
  ))

  app_env <- new.env(parent = globalenv())
  app_path <- testthat::test_path("..", "..", "inst", "app", "app.R")
  expect_no_error(sys.source(app_path, envir = app_env))
  expect_true(exists("ui", envir = app_env, inherits = FALSE))
  expect_true(exists("server", envir = app_env, inherits = FALSE))
})

test_that("package source contains no network primitives", {
  files <- list.files(
    testthat::test_path("..", "..", "R"),
    pattern = "\\.[Rr]$",
    full.names = TRUE
  )
  pattern <- paste(
    "\\burl\\(",
    "download\\.file",
    "socketConnection",
    "\\bhttr\\b",
    "\\bcurl\\b",
    "\\bRCurl\\b",
    "GET\\(",
    "POST\\(",
    "nsl\\(",
    "browseURL\\(",
    sep = "|"
  )

  matches <- unlist(lapply(files, function(path) {
    lines <- readLines(path, warn = FALSE)
    hit <- grep(pattern, lines, perl = TRUE)
    if (!length(hit)) return(character())
    sprintf("%s:%d:%s", basename(path), hit, lines[hit])
  }), use.names = FALSE)

  expect_true(length(matches) == 0, info = paste(matches, collapse = "\n"))
})
