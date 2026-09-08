# External-oracle expectations in this file were derived offline with
# sdcMicro 5.8.2 and then hardcoded here to keep CI self-contained.
#
# Oracle expression used for each fixture:
#   sdc_input <- fixture
#   sdc_input[qi_cols] <- lapply(
#     sdc_input[qi_cols],
#     function(x) factor(as.character(x))
#   )
#   obj <- sdcMicro::createSdcObj(dat = sdc_input, keyVars = qi_cols)
#   fk <- as.numeric(obj@risk$individual[, "fk"])
#   min(fk)
#   sum(fk < k)
#
# In sdcMicro::freqCalc() docs/source, key values with NA are wildcard
# matches (alpha = 1 default), so NA-heavy fixtures intentionally diverge
# from DataGangeR's NA-as-level convention.
#
# Direction of that divergence, which is the point of this file: sdcMicro's
# wildcard matching can only ever ADD records to an equivalence class, so
# fk_sdcMicro >= cell_size_dataganger for every record. DataGangeR is
# therefore always equal or MORE conservative, never less. Scenarios A-F
# found no case where DataGangeR called a cell safe that sdcMicro called
# risky. A future change that reverses this direction is a defect.

test_that("scenario A: clean categorical QIs match the external oracle", {
  df <- data.frame(
    region = c(rep("ON", 6), rep("QC", 4), rep("BC", 4)),
    sex = c(
      rep("F", 3), rep("M", 3),
      rep("F", 2), rep("M", 2),
      rep("F", 2), rep("M", 2)
    ),
    stringsAsFactors = FALSE
  )

  res <- assess_kanonymity(df, qi_cols = c("region", "sex"), k = 3)

  # sdcMicro oracle: min(fk) = 2, sum(fk < 3) = 8
  expect_equal(res$smallest_cell, 2L)
  expect_equal(res$n_below, 8L)
})

test_that("scenario B: NA handling diverges in the conservative direction", {
  df <- data.frame(
    age_band = c("A", "A", "A", "B", "B", "B", NA, NA),
    sex = c("F", "F", "M", "F", "M", "M", "F", "M"),
    stringsAsFactors = FALSE
  )

  res <- assess_kanonymity(df, qi_cols = c("age_band", "sex"), k = 3)

  # sdcMicro oracle: min(fk) = 2, sum(fk < 3) = 2
  # DataGangeR treats NA as a concrete level, so it reports more risk.
  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 8L)
  expect_lt(res$smallest_cell, 2L)
  expect_gt(res$n_below, 2L)
})

test_that("scenario C: coarsened numeric and Date QIs match the external oracle", {
  raw <- data.frame(
    age = c(21, 22, 23, 31, 32, 33, 41, 42, 43, 51, 52, 53),
    visit_date = as.Date(c(
      "2024-01-10", "2024-01-11", "2024-01-12",
      "2024-02-10", "2024-02-11", "2024-02-12",
      "2024-03-10", "2024-03-11", "2024-03-12",
      "2024-04-10", "2024-04-11", "2024-04-12"
    )),
    stringsAsFactors = FALSE
  )

  df <- raw
  df$age <- coarsen_qi_step(raw$age, step = 1L)
  df$visit_date <- coarsen_qi_step(raw$visit_date, step = 1L)

  res <- assess_kanonymity(df, qi_cols = c("age", "visit_date"), k = 3)

  expect_true(is.character(df$age))
  expect_true(inherits(df$visit_date, "Date"))
  # sdcMicro oracle on the coarsened frame: min(fk) = 1, sum(fk < 3) = 12
  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 12L)
})

test_that("scenario D: feasible enforce_kanon output still satisfies external k check", {
  syn <- data.frame(
    cat = c(rep("A", 30), rep("B", 30), rep("C", 2)),
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = "cat",
    disclosure_role = "quasi",
    stringsAsFactors = FALSE
  )

  out <- enforce_kanon(syn, roles = roles, k = 5)
  info <- attr(out, "kanon")
  res <- assess_kanonymity(out, qi_cols = "cat", k = 5)

  expect_false(isTRUE(info$infeasible))
  expect_equal(res$smallest_cell, 30L)
  expect_equal(res$n_below, 0L)
  # The guarantee itself: every surviving cell is at least k.
  expect_gte(res$smallest_cell, info$k)
  # sdcMicro oracle on the returned frame: min(fk) = 62, sum(fk < 5) = 0.
  # 62 rather than 30 because the 32 blanked rows are wildcard matches under
  # sdcMicro's NA model, so it can only ever report a larger class than
  # DataGangeR does. The external check agrees the output satisfies k.
  expect_equal(nrow(out), 62L)

  # Documents a real and deliberately visible behaviour: whole-cell
  # suppression blanked 32/62 rows (52%) even though max_suppress_frac is
  # 0.2. The backstop is evaluated on the 2 rows below k (2/62 = 3%) BEFORE
  # the NA-absorption loop, which then blanks an entire 30-row cell to lift
  # the 2-row NA bucket up to k. suppressed_row_frac exists precisely so this
  # cannot stay hidden; it must keep being reported.
  expect_equal(info$suppressed_rows, 32L)
  expect_gt(info$suppressed_row_frac, 0.2)
})

test_that("scenario E: infeasible backstop returns honest unprotected output", {
  syn <- data.frame(
    code = sprintf("X%02d", 1:10),
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = "code",
    disclosure_role = "quasi",
    stringsAsFactors = FALSE
  )

  out <- suppressWarnings(
    enforce_kanon(syn, roles = roles, k = 5, max_suppress_frac = 0.2)
  )
  info <- attr(out, "kanon")
  res <- assess_kanonymity(out, qi_cols = "code", k = 5)

  expect_true(isTRUE(info$infeasible))
  expect_equal(info$suppressed_cells, 0L)
  expect_equal(info$suppressed_rows, 0L)
  expect_equal(info$smallest_cell, 1L)
  expect_lt(info$smallest_cell, info$k)
  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 10L)
  # sdcMicro oracle on returned frame: min(fk) = 1, sum(fk < 5) = 10
  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 10L)
})

test_that("scenario F: factor-code keys avoid adversarial string collisions", {
  # The literal "<NA>" string and a genuine NA must not merge: kanon_key()'s
  # comment records that an earlier version pasted values under a "\u0001"
  # separator and mapped NA to the literal "<NA>", so either a control
  # character or that exact text could fuse two distinct combinations and
  # understate risk. Row 8 carries the literal text, row 12 a real NA.
  df <- data.frame(
    a = c(
      rep("x\u0001y", 3), rep("x", 2),
      "alpha,beta", "alpha", "<NA>", "<NA>", "plain", "plain", NA
    ),
    b = c(
      rep("z", 3), rep("y\u0001z", 2),
      "gamma", "beta,gamma", "t", "u", "v,w", "v,w", "t"
    ),
    stringsAsFactors = FALSE
  )

  keys <- kanon_key(df, qi_cols = c("a", "b"))
  key_sizes <- sort(as.integer(table(keys)))
  res <- assess_kanonymity(df, qi_cols = c("a", "b"), k = 3)

  expect_equal(length(unique(keys)), nrow(unique(df[c("a", "b")])))
  expect_equal(key_sizes, c(1L, 1L, 1L, 1L, 1L, 2L, 2L, 3L))
  # "x\u0001y" + "z" must not fuse with "x" + "y\u0001z".
  expect_false(identical(keys[1], keys[4]))
  # "alpha,beta" + "gamma" must not fuse with "alpha" + "beta,gamma", which
  # is the collision a comma-joined key of raw values would produce.
  expect_false(identical(keys[6], keys[7]))
  # Literal "<NA>" must not fuse with a genuine NA.
  expect_false(identical(keys[8], keys[12]))
  # sdcMicro oracle: min(fk) = 1, sum(fk < 3) = 9
  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 9L)
})
