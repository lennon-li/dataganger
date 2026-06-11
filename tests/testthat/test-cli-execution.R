test_that("profile command writes profile JSON", {
  tmp <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path <- file.path(tmp, "profile.json")

  result <- run_cli(c("profile", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  profile <- jsonlite::read_json(out_path, simplifyVector = TRUE)
  expect_equal(profile$n_rows, 5)
  expect_equal(profile$n_cols, 4)
  expect_true("profile" %in% names(profile))
  expect_true("n_missing" %in% names(profile$profile))
  expect_true(any(profile$profile$variable == "score"))
})

test_that("roles command writes roles YAML", {
  tmp <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path <- file.path(tmp, "roles.yaml")

  result <- run_cli(c("roles", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  roles <- yaml::read_yaml(out_path)
  expect_true("roles" %in% names(roles))
  expect_true(any(vapply(roles$roles, function(x) identical(x$variable, "id"), logical(1))))
  expect_true(any(vapply(roles$roles, function(x) identical(x$variable, "score"), logical(1))))
})
