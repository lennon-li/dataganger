test_that("roles survive a YAML round-trip with both axes and actions", {
  df <- data.frame(age = 1:5, name = letters[1:5], stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  roles$identifies[roles$variable == "age"]  <- "combination"
  roles$identifies[roles$variable == "name"] <- "none"
  roles$sensitive[roles$variable == "age"]   <- TRUE
  roles <- dg_sync_roles_axes(roles)

  tmp <- withr::local_tempfile(fileext = ".yaml")
  cli_write_yaml(roles_to_yaml_list(roles), tmp)
  rt <- cli_read_roles_yaml(tmp, df)

  for (col in c("variable", "identifies", "sensitive", "simulation")) {
    expect_equal(rt[[col]], roles[[col]], info = col)
  }
})

test_that("cli_read_roles_yaml preserves disclosure_role when axes are omitted", {
  tmp <- withr::local_tempfile(fileext = ".yml")
  df <- data.frame(age = 1:10)
  yaml::write_yaml(list(roles = list(list(variable = "age", disclosure_role = "quasi"))), tmp)

  roles <- cli_read_roles_yaml(tmp, df)

  expect_equal(roles$disclosure_role[roles$variable == "age"], "quasi")
  expect_equal(roles$identifies[roles$variable == "age"], "combination")
})
