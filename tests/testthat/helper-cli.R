cli_fixture_csv <- function(tmp = withr::local_tempdir()) {
  path <- file.path(tmp, "fixture.csv")
  readr::write_csv(
    tibble::tibble(
      id = 1:5,
      group = factor(c("a", "a", "b", "b", "c")),
      score = c(10, NA, 12, 13, 14),
      note = c("alpha", "beta", "gamma", "delta", "epsilon")
    ),
    path
  )
  path
}

run_cli <- function(args) {
  out <- capture.output(
    msg <- capture.output(code <- dataganger_cli(args, quit = FALSE), type = "message")
  )
  list(code = code, output = out, messages = msg)
}
