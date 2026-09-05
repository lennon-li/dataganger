# Tests for compare_synthetic() -- [3.1]-[3.5]

test_that("compare_synthetic() returns dataganger_comparison", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  spec <- synth_spec(purpose = "demo")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_s3_class(cmp, "dataganger_comparison")
  expect_named(cmp, c("dataset", "numeric", "categorical", "relationship", "interaction",
                      "utility", "disclosure", "privacy_flags", "meta"))
})

test_that("compare_synthetic() includes relationship interactions", {
  set.seed(201)
  original <- data.frame(
    predictor = stats::rnorm(120),
    outcome = stats::rnorm(120),
    group = factor(rep(c("a", "b"), 60))
  )
  synthetic <- original

  interaction <- compare_synthetic(original, synthetic)$interaction

  expect_named(interaction, c(
    "predictor", "outcome", "family", "effect_label", "estimate",
    "null_value", "p_value", "n_terms", "note"
  ))
  expect_equal(nrow(interaction), choose(3, 2))
  expect_identical(interaction$predictor[[1]], "predictor")
  expect_identical(interaction$outcome[[1]], "outcome")
})

test_that("compare_synthetic() dataset-level metrics", {
  df <- data.frame(x = 1:10, y = rnorm(10))
  spec <- synth_spec(purpose = "demo", n = 20)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  ds <- cmp$dataset
  expect_equal(ds$original[ds$metric == "nrow"], 10)
  expect_equal(ds$synthetic[ds$metric == "nrow"], 20)
  expect_equal(ds$original[ds$metric == "ncol"], 2)
  expect_true(ds$value[ds$metric == "type_match_pct"] > 0)
})

test_that("compare_synthetic() numeric comparison", {
  df <- data.frame(a = rnorm(50, 10, 2), b = rnorm(50, 5, 1))
  spec <- synth_spec(purpose = "demo", n = 100, seed = 1)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  num <- cmp$numeric
  expect_true(nrow(num) >= 1)
  expect_true("std_diff" %in% names(num))
  expect_true("mean_orig" %in% names(num))
  expect_true("mean_syn" %in% names(num))
})

test_that("compare_synthetic() standardized diff is computed correctly", {
  df <- data.frame(x = c(1:4, 5))
  spec <- synth_spec(purpose = "demo", n = 5, seed = 1)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(!is.na(cmp$numeric$std_diff[1]))
})

test_that("compare_synthetic() categorical comparison", {
  df <- data.frame(f = factor(rep(c("a", "b", "c"), each = 5)))
  spec <- synth_spec(purpose = "demo", n = 30)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  cat <- cmp$categorical
  expect_true(nrow(cat) >= 1)
  expect_true("tvd" %in% names(cat))
  expect_true("n_levels_orig" %in% names(cat))
  expect_true("n_levels_syn" %in% names(cat))
})

test_that("compare_synthetic() TVD is between 0 and 1", {
  df <- data.frame(f = factor(rep(c("x", "y"), each = 10)))
  spec <- synth_spec(purpose = "demo", n = 50)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(cmp$categorical$tvd[1] >= 0)
  expect_true(cmp$categorical$tvd[1] <= 1)
})

test_that("compare_synthetic() relationship with 2+ numeric columns", {
  df <- data.frame(a = 1:20, b = 20:1, c = rnorm(20))
  spec <- synth_spec(purpose = "demo", n = 20)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(nrow(cmp$relationship) >= 1)
  expect_true("cor_orig" %in% names(cmp$relationship))
  expect_true("cor_syn" %in% names(cmp$relationship))
  expect_true("cor_diff" %in% names(cmp$relationship))
})

test_that("compare_synthetic() relationship with <2 numeric columns is empty", {
  df <- data.frame(x = letters[1:10], y = factor(rep("a", 10)))
  spec <- synth_spec(purpose = "demo", n = 10)
  syn <- synthesize_data(df, spec)
  expect_message(
    cmp <- compare_synthetic(df, syn),
    "Not enough numeric"
  )
  expect_equal(nrow(cmp$relationship), 0)
})

test_that("compare_synthetic() handles all-NA numeric column", {
  df <- data.frame(x = rep(NA_real_, 10), y = 1:10)
  spec <- synth_spec(purpose = "demo", n = 5)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(nrow(cmp$numeric) >= 1)
  expect_true(is.na(cmp$numeric$std_diff[cmp$numeric$variable == "x"]))
})

test_that("compare_synthetic() handles no numeric columns", {
  df <- data.frame(x = letters[1:5], y = factor(letters[1:5]))
  spec <- synth_spec(purpose = "demo", n = 5)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_equal(nrow(cmp$numeric), 0)
})

test_that("compare_synthetic() handles no categorical columns", {
  df <- data.frame(x = 1:5, y = 6:10)
  spec <- synth_spec(purpose = "demo", n = 5)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_equal(nrow(cmp$categorical), 0)
})

test_that("compare_numeric emits sd_ratio, median_std_diff, and test p-values", {
  set.seed(1)
  orig <- data.frame(x = rnorm(200, 10, 2))
  syn  <- data.frame(x = rnorm(200, 10, 2))
  cn <- compare_numeric(orig, syn)

  expect_true(
    all(c("sd_ratio", "median_std_diff",
          "mean_p", "sd_p", "median_p") %in% names(cn)),
    info = paste("Numeric comparison columns:", paste(names(cn), collapse = ", "))
  )
  expect_equal(cn$sd_ratio, cn$sd_syn / cn$sd_orig)
  expect_equal(cn$median_std_diff,
               (cn$median_syn - cn$median_orig) / cn$iqr_orig)
  expect_gt(cn$mean_p, 0.05)
  expect_gt(cn$sd_p, 0.05)
  expect_gt(cn$median_p, 0.05)

  syn2 <- data.frame(x = rnorm(200, 14, 2))
  cn2 <- compare_numeric(orig, syn2)
  expect_lt(cn2$mean_p, 0.05)

  cn3 <- compare_numeric(data.frame(x = rep(5, 3)), data.frame(x = rep(5, 3)))
  expect_true(is.na(cn3$sd_ratio) || is.finite(cn3$sd_ratio))
  expect_true(is.na(cn3$mean_p))
})

test_that("compare_synthetic() rejects non-data-frame", {
  expect_error(
    compare_synthetic("not a df", data.frame(x = 1:3)),
    "must be a data frame"
  )
})

test_that("compare_synthetic() print method works", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  spec <- synth_spec(purpose = "demo")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_no_error(print(cmp))
})

test_that("compare_synthetic() meta includes generation time", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "demo")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_s3_class(cmp$meta$generated_at, "POSIXct")
  expect_equal(cmp$meta$nrow_orig, 5)
  expect_equal(cmp$meta$ncol_orig, 1)
})

test_that("compare_synthetic() categorical comparison for character columns", {
  df <- data.frame(txt = c("hello", "world", "hello", "foo", "bar"))
  spec <- synth_spec(purpose = "demo", n = 20, merge_rare = FALSE)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(nrow(cmp$categorical) >= 1)
})

# ---- Global utility (pMSE / S_pMSE) [SYN-2] ------------------------------

test_that("compare_utility() gives near-zero pMSE when a predictor carries no group signal", {
  # x repeats identically across both halves of the stacked data (deterministic,
  # no seed needed), so it carries zero information about which dataset a row
  # came from -- the fitted logistic coefficient should be ~0 and every row's
  # predicted probability should land at the base rate, driving pMSE to ~0.
  orig <- data.frame(x = 1:100)
  syn  <- data.frame(x = 1:100)
  u <- compare_utility(orig, syn)
  expect_true(is.finite(u$pmse))
  expect_lt(u$pmse, 0.01)
  expect_true(is.na(u$note))
})

test_that("compare_utility() gives a higher S_pMSE when datasets are fully separable", {
  symmetric  <- compare_utility(data.frame(x = 1:100), data.frame(x = 1:100))
  separable  <- compare_utility(data.frame(x = 1:50), data.frame(x = 1000:1049))
  expect_true(is.finite(separable$s_pmse))
  expect_true(is.finite(symmetric$s_pmse))
  expect_gt(separable$s_pmse, symmetric$s_pmse)
})

test_that("compare_utility() returns NA gracefully with no usable shared columns", {
  orig <- data.frame(a = 1:10)
  syn  <- data.frame(b = 1:10)
  u <- compare_utility(orig, syn)
  expect_true(is.na(u$pmse))
  expect_true(is.na(u$s_pmse))
  expect_false(is.na(u$note))
})

test_that("compare_utility() returns NA gracefully with too few rows", {
  u <- compare_utility(data.frame(x = 1), data.frame(x = 2))
  expect_true(is.na(u$pmse))
  expect_false(is.na(u$note))
})

test_that("compare_synthetic() wires utility into the full comparison, mixed types", {
  df <- data.frame(
    amount = rnorm(60, 10, 2),
    grp    = rep(c("a", "b", "c"), 20),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "demo", n = 60, seed = 1)
  syn  <- synthesize_data(df, spec)
  cmp  <- compare_synthetic(df, syn)
  expect_named(cmp$utility, c("pmse", "pmse_expected", "s_pmse", "n_predictors", "note"))
  expect_true(is.finite(cmp$utility$pmse))
  expect_true(is.finite(cmp$utility$s_pmse))
})

test_that("compare_synthetic() print method includes a Utility section that is not a privacy claim", {
  df <- data.frame(x = rnorm(40), y = rep(c("a", "b"), 20), stringsAsFactors = FALSE)
  spec <- synth_spec(purpose = "demo", n = 40, seed = 1)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  # cli writes through message(), which capture.output() (stdout only) does
  # not see -- capture messages explicitly, matching how cli output is
  # actually emitted.
  out <- paste(testthat::capture_messages(print(cmp)), collapse = "\n")
  expect_match(out, "Utility")
  expect_match(out, "[Nn]ot a privacy")
})

test_that("plot_comparison() errors if ggplot2 missing", {
  skip_if(
    requireNamespace("ggplot2", quietly = TRUE),
    "ggplot2 is installed"
  )
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "demo")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_error(plot_comparison(cmp))
})

test_that("plot_comparison() returns plots when ggplot2 available", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(x = rnorm(20), f = factor(rep(c("a", "b"), 10)))
  spec <- synth_spec(purpose = "demo", n = 20, seed = 1)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  p <- plot_comparison(cmp)
  expect_type(p, "list")
  expect_true(!is.null(p$numeric))
  expect_true(!is.null(p$categorical))
})

test_that("compare_synthetic() works with toy dataset", {
  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "development", seed = 1)
  syn <- synthesize_data(example_health_survey, spec)
  cmp <- compare_synthetic(example_health_survey, syn)
  expect_s3_class(cmp, "dataganger_comparison")
  expect_true(nrow(cmp$numeric) > 0)
  expect_true(nrow(cmp$categorical) > 0)
})

test_that("post-synthesis comparison survives generic column renaming", {
  original <- data.frame(
    age = rep(20:29, each = 4),
    group = rep(c("a", "b"), 20),
    score = seq_len(40),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(original)
  roles$identifies <- "none"
  roles$sensitive <- FALSE
  roles$disclosure_role <- "none"

  spec_preserve <- synth_spec(purpose = "development", seed = 101, n = 40, name_strategy = "preserve")
  spec_generic <- synth_spec(purpose = "development", seed = 101, n = 40, name_strategy = "generic")
  syn_preserve <- synthesize_data(original, spec_preserve, roles = roles)
  syn_generic <- synthesize_data(original, spec_generic, roles = roles)

  flags_preserve <- privacy_check(original, syn_preserve, roles = roles, stage = "post", spec = spec_preserve)
  flags_generic <- privacy_check(original, syn_generic, roles = roles, stage = "post", spec = spec_generic)
  cmp_preserve <- compare_synthetic(original, syn_preserve, roles = roles)
  cmp_generic <- compare_synthetic(original, syn_generic, roles = roles)

  expect_equal(flags_generic$variable, flags_preserve$variable)
  expect_equal(flags_generic$flag, flags_preserve$flag)
  expect_equal(cmp_generic$numeric$variable, cmp_preserve$numeric$variable)
  expect_gt(nrow(cmp_generic$numeric), 0)
  expect_equal(
    exact_row_match_count(original, dg_original_names(syn_generic)),
    exact_row_match_count(original, syn_preserve)
  )
})

# ---- Disclosure risk (synthpop) [SYN-1] ----------------------------------

test_that("compare_disclosure() extracts keys and target from roles", {
  orig <- data.frame(
    age = c(25, 30, 35, 40),
    sex = c("M", "F", "M", "F"),
    income = c(50000, 60000, 70000, 80000),
    notes = c("n1", "n2", "n3", "n4"),
    stringsAsFactors = FALSE
  )
  syn <- orig

  # Via identifies and sensitive
  roles1 <- data.frame(
    variable = c("age", "sex", "income", "notes"),
    identifies = c("quasi", "quasi", "none", "none"),
    sensitive = c(FALSE, FALSE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  d1 <- compare_disclosure(orig, syn, roles1)
  expect_true(d1$available)
  expect_equal(sort(d1$keys), c("age", "sex"))
  expect_equal(d1$target, "income")

  # Via disclosure_role
  roles2 <- data.frame(
    variable = c("age", "sex", "income", "notes"),
    disclosure_role = c("quasi", "quasi", "sensitive", "none"),
    stringsAsFactors = FALSE
  )
  d2 <- compare_disclosure(orig, syn, roles2)
  expect_true(d2$available)
  expect_equal(sort(d2$keys), c("age", "sex"))
  expect_equal(d2$target, "income")
})

test_that("compare_disclosure() returns expected structure and values", {
  skip_if_not_installed("synthpop")

  orig <- data.frame(
    k1 = c(1, 2, 3, 4, 5, 5),
    k2 = c("a", "b", "c", "d", "e", "e"),
    target = c("t1", "t2", "t1", "t2", "t1", "t2"),
    stringsAsFactors = FALSE
  )
  syn <- orig

  roles <- data.frame(
    variable = c("k1", "k2", "target"),
    identifies = c("quasi", "quasi", "none"),
    sensitive = c(FALSE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )

  res <- compare_disclosure(orig, syn, roles)
  expect_true(res$available)
  expect_true(is.na(res$note))
  expect_equal(sort(res$keys), c("k1", "k2"))
  expect_equal(res$target, "target")
  expect_true("repU_pct" %in% names(res))
  expect_true("repU_count" %in% names(res))
  expect_true("orig_uniques" %in% names(res))
  expect_true("orig_uniques_pct" %in% names(res))
  expect_true("disco_pct" %in% names(res))

  # There are 4 unique records in orig out of 6 rows (rows 1 to 4)
  expect_equal(res$orig_uniques, 4L)
  expect_equal(res$repU_count, 4L)
  expect_equal(res$repU, res$repU_pct)
  expect_true(is.numeric(res$repU_pct))
  expect_true(is.numeric(res$disco_pct))

  # Synthetic where none of the uniques replicate
  syn_diff <- orig
  syn_diff$k1 <- syn_diff$k1 + 100
  res_diff <- compare_disclosure(orig, syn_diff, roles)
  expect_true(res_diff$available)
  expect_equal(res_diff$orig_uniques, 4L)
  expect_equal(res_diff$repU_count, 0L)
  expect_equal(res_diff$repU_pct, 0)
})

test_that("compare_disclosure() handles roles = NULL gracefully", {
  orig <- data.frame(x = 1:5, y = letters[1:5])
  syn <- orig
  res <- compare_disclosure(orig, syn, roles = NULL)
  expect_false(res$available)
  expect_match(res$note, "Roles must be provided")
  expect_equal(res$keys, character(0))
  expect_equal(res$target, character(0))
  expect_true(is.na(res$repU))
  expect_true(is.na(res$repU_count))
  expect_true(is.na(res$orig_uniques))
  expect_true(is.na(res$orig_uniques_pct))
  expect_true(is.na(res$repU_pct))
  expect_true(is.na(res$disco_pct))
})

test_that("compare_disclosure() handles missing quasi-identifiers gracefully", {
  orig <- data.frame(x = 1:5, y = letters[1:5])
  syn <- orig
  roles <- data.frame(
    variable = c("x", "y"),
    identifies = c("none", "none"),
    sensitive = c(FALSE, FALSE),
    stringsAsFactors = FALSE
  )
  res <- compare_disclosure(orig, syn, roles = roles)
  expect_false(res$available)
  expect_match(res$note, "No quasi-identifier")
  expect_equal(res$keys, character(0))
  expect_true(is.na(res$repU))
})

test_that("compare_disclosure() handles missing synthpop gracefully", {
  testthat::with_mocked_bindings(
    requireNamespace = function(pkg, ...) if (pkg == "synthpop") FALSE else base::requireNamespace(pkg, ...),
    .package = "base",
    code = {
      orig <- data.frame(k = 1:5)
      roles <- data.frame(variable = "k", identifies = "quasi", stringsAsFactors = FALSE)
      res <- compare_disclosure(orig, orig, roles = roles)
      expect_false(res$available)
      expect_match(res$note, "Package synthpop is required")
      expect_equal(res$keys, character(0))
      expect_equal(res$target, character(0))
      expect_true(is.na(res$repU))
      expect_true(is.na(res$repU_pct))
    }
  )
})

test_that("compare_synthetic() integrates disclosure and print method shows sections", {
  orig <- data.frame(
    age = c(20, 25, 30, 35, 40, 40),
    sex = c("M", "F", "M", "F", "M", "M"),
    income = c(30, 40, 50, 60, 70, 70),
    stringsAsFactors = FALSE
  )
  syn <- orig
  roles <- data.frame(
    variable = c("age", "sex", "income"),
    identifies = c("quasi", "quasi", "none"),
    sensitive = c(FALSE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )

  cmp <- compare_synthetic(orig, syn, roles = roles)
  expect_true("disclosure" %in% names(cmp))
  expect_true(cmp$disclosure$available)

  # Check print output when available
  out <- paste(testthat::capture_messages(print(cmp)), collapse = "\n")
  expect_match(out, "Disclosure risk")
  expect_match(out, "Keys:")
  expect_match(out, "Replicated uniques")
  expect_match(out, "DiSCO")
  expect_match(out, "does not guarantee immunity from re-identification")

  # Check print output when unavailable (roles = NULL)
  cmp_noroles <- compare_synthetic(orig, syn, roles = NULL)
  expect_false(cmp_noroles$disclosure$available)
  out_noroles <- paste(testthat::capture_messages(print(cmp_noroles)), collapse = "\n")
  expect_match(out_noroles, "Disclosure risk")
  expect_match(out_noroles, "Not computed:")
})

test_that("compare_disclosure() handles tibble inputs and calculates DiSCO without xtfrm errors", {
  skip_if_not_installed("synthpop")
  skip_if_not_installed("tibble")

  orig_tbl <- tibble::tibble(
    age = c(20, 25, 30, 35, 40),
    sex = c("M", "F", "M", "F", "M"),
    income = c(30000, 40000, 50000, 60000, 70000)
  )
  syn_tbl <- orig_tbl

  roles <- tibble::tibble(
    variable = c("age", "sex", "income"),
    identifies = c("quasi", "quasi", "none"),
    sensitive = c(FALSE, FALSE, TRUE)
  )

  res <- compare_disclosure(orig_tbl, syn_tbl, roles)
  expect_true(res$available)
  expect_equal(sort(res$keys), c("age", "sex"))
  expect_equal(res$target, "income")
  expect_false(is.na(res$disco_pct))
  expect_equal(res$disco_pct, 100)
})
