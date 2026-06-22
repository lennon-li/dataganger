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

test_that("enforce_kanon NA bucket is padded to k when initial suppression creates a small bucket", {
  # Regression: when only a few rows are blanked they collapse into a single
  # NA bucket that itself violates k. The fix absorbs more rows until NA >= k.
  set.seed(7)
  syn <- data.frame(
    sex  = sample(c("F", "M"), 120, replace = TRUE),
    city = sample(c("Toronto", "Montreal"), 120, replace = TRUE),
    rare = c(rep("common", 118), "uniqA", "uniqB"),
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = c("sex", "city", "rare"),
    disclosure_role = c("quasi", "quasi", "quasi"),
    stringsAsFactors = FALSE
  )
  out <- enforce_kanon(syn, roles = roles, k = 8)
  info <- attr(out, "kanon")
  expect_false(is.null(info))
  res <- assess_kanonymity(out, info$qi_cols, k = 8)
  # Every non-NA cell AND the NA bucket must be >= 8
  expect_true(is.na(res$smallest_cell) || res$smallest_cell >= 8,
    info = sprintf("smallest_cell = %s", res$smallest_cell))
})

test_that("synthesize_data emits k-anonymous output over quasi-identifiers", {
  set.seed(42)
  df <- data.frame(
    patient_id = sprintf("P%04d", 1:200),
    sex  = sample(c("F", "M"), 200, TRUE),
    band = sample(c("a", "b", "c"), 200, TRUE),
    rare = c(rep("common", 198), "uniqueX", "uniqueY"),
    val  = rnorm(200),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  roles$disclosure_role[roles$variable == "rare"] <- "quasi"
  spec <- synth_spec(purpose = "demo", k_anon = 5)

  syn <- synthesize_data(df, spec = spec, roles = roles)

  expect_false("patient_id" %in% names(syn))
  info <- attr(syn, "kanon")
  expect_false(is.null(info))
  if (length(info$qi_cols)) {
    res <- assess_kanonymity(syn, info$qi_cols, k = 5)
    expect_true(is.na(res$smallest_cell) || res$smallest_cell >= 5)
  }
})
