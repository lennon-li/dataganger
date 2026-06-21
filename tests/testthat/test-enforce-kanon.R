pkgload::load_all(".", quiet = TRUE, export_all = TRUE)

test_that("coarsen_geography truncates postal/zip-like codes by one level", {
  x <- c("M5V 3A8", "M5V 2T6", "90210", "90213")
  out1 <- coarsen_geography(x, level = 1)
  expect_equal(out1, c("M5V3A", "M5V2T", "9021", "9021"))

  out2 <- coarsen_geography(x, level = 2)
  expect_equal(out2, c("M5V3", "M5V2", "902", "902"))
})

test_that("enforce_kanon removes direct identifiers from output", {
  syn <- data.frame(
    id  = sprintf("P%03d", 1:20),
    sex = rep(c("F", "M"), 10),
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = c("id", "sex"),
    disclosure_role = c("direct", "quasi"),
    stringsAsFactors = FALSE
  )
  out <- enforce_kanon(syn, roles = roles, k = 5)
  expect_false("id" %in% names(out))
})

test_that("enforce_kanon leaves output with no QI cell smaller than k", {
  syn <- data.frame(
    cat = c(rep("A", 30), rep("B", 30), rep("C", 2)),
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = "cat", disclosure_role = "quasi", stringsAsFactors = FALSE
  )
  out <- enforce_kanon(syn, roles = roles, k = 5)
  tab <- table(out$cat[!is.na(out$cat)])
  expect_true(all(tab >= 5))
})

test_that("enforce_kanon suppresses residual cells that cannot reach k", {
  syn <- data.frame(
    code = sprintf("X%02d", 1:10), stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = "code", disclosure_role = "quasi", stringsAsFactors = FALSE
  )
  out <- enforce_kanon(syn, roles = roles, k = 5)
  expect_true(all(is.na(out$code)))
  info <- attr(out, "kanon")
  expect_true(info$suppressed_cells >= 1)
})
