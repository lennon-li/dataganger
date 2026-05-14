# Tests for synthesize_data() — [2.9]-[2.14]

# ---- Schema synthesis ----

test_that("synthesize_data() schema level returns 0-row tibble", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  spec <- synth_spec(purpose = "safer_external", name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn, "dataganger_synthetic")
  expect_s3_class(syn, "tbl_df")
  expect_equal(nrow(syn), 0)
  expect_equal(ncol(syn), 2)
  expect_named(syn, c("x", "y"))
})

test_that("synthesize_data() schema preserves types", {
  df <- data.frame(
    num  = 1:3,
    chr  = letters[1:3],
    fac  = factor(c("a", "b", "c")),
    lgl  = c(TRUE, FALSE, TRUE),
    dt   = as.Date(c("2024-01-01", "2024-02-01", "2024-03-01")),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "safer_external", name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_type(syn$num, "double")
  expect_type(syn$chr, "character")
  expect_s3_class(syn$fac, "factor")
  expect_type(syn$lgl, "logical")
  expect_s3_class(syn$dt, "Date")
})

test_that("synthesize_data() schema with haven_labelled", {
  df <- data.frame(
    status = haven::labelled(c(1, 2, 1), labels = c(A = 1, B = 2)),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "safer_external")
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 0)
  expect_equal(ncol(syn), 1)
})

# ---- Marginal synthesis ----

test_that("synthesize_data() marginal returns correct dimensions", {
  df <- data.frame(x = 1:10, y = letters[1:10])
  spec <- synth_spec(purpose = "teaching", n = 20)
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 20)
  expect_equal(ncol(syn), 2)
  expect_s3_class(syn, "dataganger_synthetic")
})

test_that("synthesize_data() marginal numeric column", {
  set.seed(1)
  df <- data.frame(val = rnorm(100, mean = 50, sd = 10))
  spec <- synth_spec(purpose = "teaching", n = 200)
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 200)
  expect_type(syn$val, "double")
  expect_true(all(syn$val >= min(df$val, na.rm = TRUE) - 1e-8))
  expect_true(all(syn$val <= max(df$val, na.rm = TRUE) + 1e-8))
})

test_that("synthesize_data() marginal factor column", {
  df <- data.frame(group = factor(rep(c("A", "B", "C"), each = 10)))
  spec <- synth_spec(purpose = "teaching", n = 50)
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn$group, "factor")
  expect_true(all(as.character(syn$group) %in% c("A", "B", "C")))
})

test_that("synthesize_data() marginal Date column", {
  df <- data.frame(
    dt = as.Date(c("2023-01-15", "2023-06-20", "2023-12-01"))
  )
  spec <- synth_spec(purpose = "teaching", n = 10)
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn$dt, "Date")
})

test_that("synthesize_data() marginal logical column", {
  df <- data.frame(flag = c(TRUE, FALSE, TRUE, TRUE))
  spec <- synth_spec(purpose = "teaching", n = 50)
  syn <- synthesize_data(df, spec)
  expect_type(syn$flag, "logical")
})

test_that("synthesize_data() marginal haven_labelled column", {
  df <- data.frame(
    status = haven::labelled(
      c(1, 2, 1, 2, 1),
      labels = c(Active = 1, Inactive = 2),
      label = "Status"
    ),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "teaching", n = 20)
  syn <- synthesize_data(df, spec)
  expect_true(haven::is.labelled(syn$status))
})

test_that("synthesize_data() marginal POSIXct column", {
  df <- data.frame(
    ts = as.POSIXct(c("2024-01-01 12:00:00", "2024-06-15 08:30:00")),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "teaching", n = 10)
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn$ts, "POSIXct")
})

test_that("synthesize_data() preserves missingness at approximate rate", {
  df <- data.frame(
    val = c(rnorm(80), rep(NA_real_, 20))
  )
  spec <- synth_spec(purpose = "teaching", n = 1000,
                     preserve_missingness = "approx")
  syn <- synthesize_data(df, spec)
  na_rate <- sum(is.na(syn$val)) / nrow(syn)
  expect_true(na_rate > 0.05 && na_rate < 0.35)
})

test_that("synthesize_data() missingness = none produces no NAs", {
  df <- data.frame(val = c(rnorm(5), NA))
  spec <- synth_spec(purpose = "teaching", n = 50,
                     preserve_missingness = "none")
  syn <- synthesize_data(df, spec)
  expect_equal(sum(is.na(syn$val)), 0)
})

# ---- Engine checks ----

test_that("synthesize_data() errors cleanly for synthpop engine", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "teaching")
  expect_error(
    synthesize_data(df, spec, engine = "synthpop"),
    "synthpop"
  )
})

test_that("synthesize_data() errors for hifi engine_required", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "internal_hifi", acknowledge_risk = TRUE)
  expect_error(
    synthesize_data(df, spec),
    "hifi engine"
  )
})

# ---- Seed reproducibility ----

test_that("synthesize_data() seed produces identical output", {
  df <- data.frame(x = rnorm(50), y = letters[1:50])
  spec <- synth_spec(purpose = "teaching", n = 30, seed = 42)
  syn1 <- synthesize_data(df, spec)
  syn2 <- synthesize_data(df, spec)
  expect_equal(syn1$x, syn2$x)
  expect_equal(syn1$y, syn2$y)
})

test_that("synthesize_data() seed isolation does not mutate global RNG", {
  df <- data.frame(x = 1:10)
  set.seed(999)
  before <- .Random.seed
  spec <- synth_spec(purpose = "teaching", n = 5, seed = 123)
  syn <- synthesize_data(df, spec)
  after <- .Random.seed
  expect_equal(before, after)
})

# ---- Edge cases ----

test_that("synthesize_data() all-NA numeric column", {
  df <- data.frame(x = rep(NA_real_, 10))
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 5)
  expect_true(all(is.na(syn$x)))
})

test_that("synthesize_data() all-NA character column", {
  df <- data.frame(x = rep(NA_character_, 10))
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  expect_true(all(is.na(syn$x)))
})

test_that("synthesize_data() all-NA haven_labelled column", {
  df <- data.frame(
    x = haven::labelled(
      rep(NA_real_, 5),
      labels = c(A = 1, B = 2)
    ),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  expect_true(all(is.na(syn$x)))
})

test_that("synthesize_data() 1-level factor does not error", {
  df <- data.frame(f = factor(rep("only", 10)))
  spec <- synth_spec(purpose = "teaching", n = 20)
  expect_no_error(syn <- synthesize_data(df, spec))
  expect_s3_class(syn$f, "factor")
})

test_that("synthesize_data() 0-row input schema works", {
  df <- data.frame(x = numeric(0), y = character(0))
  spec <- synth_spec(purpose = "safer_external")
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 0)
  expect_equal(ncol(syn), 2)
})

test_that("synthesize_data() 0-row input marginal works", {
  df <- data.frame(x = numeric(0), y = character(0))
  spec <- synth_spec(purpose = "teaching", n = 0)
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 0)
  expect_equal(ncol(syn), 2)
})

test_that("synthesize_data() 1-row input does not error", {
  df <- data.frame(x = 42, y = "hello")
  spec <- synth_spec(purpose = "teaching", n = 10)
  expect_no_error(syn <- synthesize_data(df, spec))
  expect_equal(nrow(syn), 10)
})

test_that("synthesize_data() 100% missing column handled", {
  df <- data.frame(
    good = 1:10,
    all_na = rep(NA_real_, 10)
  )
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  expect_true(all(is.na(syn$all_na)))
  expect_false(all(is.na(syn$good)))
})

# ---- Name strategies ----

test_that("synthesize_data() name_strategy 'generic' renames columns", {
  df <- data.frame(patient_name = 1:5, age_years = 21:25)
  spec <- synth_spec(purpose = "teaching", n = 5, name_strategy = "generic")
  syn <- synthesize_data(df, spec)
  expect_named(syn, c("col_1", "col_2"))
})

test_that("synthesize_data() name_strategy 'dictionary_only' renames and stores map", {
  df <- data.frame(patient_name = 1:5, age_years = 21:25)
  spec <- synth_spec(purpose = "teaching", n = 5,
                     name_strategy = "dictionary_only")
  syn <- synthesize_data(df, spec)
  expect_named(syn, c("col_1", "col_2"))
  expect_true(!is.null(attr(syn, "name_map")))
  expect_equal(attr(syn, "name_map")[["col_1"]], "patient_name")
  expect_equal(attr(syn, "name_map")[["col_2"]], "age_years")
})

test_that("synthesize_data() name_strategy 'preserve' keeps original names", {
  df <- data.frame(patient_name = 1:5, age_years = 21:25)
  spec <- synth_spec(purpose = "teaching", n = 5, name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_named(syn, c("patient_name", "age_years"))
})

# ---- Attributes ----

test_that("synthesize_data() returns correct attributes", {
  df <- data.frame(x = 1:10)
  spec <- synth_spec(purpose = "teaching", n = 5, seed = 7)
  syn <- synthesize_data(df, spec)
  expect_true(!is.null(attr(syn, "spec")))
  expect_equal(attr(syn, "original_dims"), list(nrow = 10, ncol = 1))
  expect_equal(attr(syn, "seed_used"), 7)
  expect_s3_class(attr(syn, "generated_at"), "POSIXct")
})

# ---- Input validation ----

test_that("synthesize_data() rejects non-data-frame", {
  expect_error(
    synthesize_data("not data", synth_spec(purpose = "teaching")),
    "must be a data frame"
  )
})

test_that("synthesize_data() rejects non-spec", {
  expect_error(
    synthesize_data(data.frame(x = 1:3), "not a spec"),
    "dataganger_spec"
  )
})

test_that("synthesize_data() roles are optional", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "teaching", n = 10)
  expect_no_error(synthesize_data(df, spec, roles = NULL))
})

test_that("synthesize_data() marginal with character column", {
  df <- data.frame(txt = rep(c("hello", "world", "foo", "bar"), each = 3))
  spec <- synth_spec(purpose = "teaching", n = 20, merge_rare = FALSE)
  syn <- synthesize_data(df, spec)
  expect_type(syn$txt, "character")
  expect_true(all(syn$txt %in% c("hello", "world", "foo", "bar", NA)))
})

test_that("synthesize_data() default n equals nrow(original)", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "teaching")  # n = NULL
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 5)
})

test_that("synthesize_data() free text dropped when strategy is drop", {
  long_strings <- sprintf("very_long_text_for_free_text_test_%040d", 1:20)
  df <- data.frame(notes = long_strings, x = 1:20)
  spec <- synth_spec(purpose = "teaching", n = 10,
                     free_text_strategy = "drop")
  syn <- synthesize_data(df, spec)
  expect_true(all(is.na(syn$notes)))
  expect_false(all(is.na(syn$x)))
})

test_that("synthesize_data() marginal mixed types all work", {
  df <- data.frame(
    n = rnorm(10),
    c = letters[1:10],
    f = factor(rep(c("x", "y"), 5)),
    l = rep(c(TRUE, FALSE), 5),
    d = as.Date("2024-01-01") + 0:9,
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "teaching", n = 30)
  expect_no_error(syn <- synthesize_data(df, spec))
  expect_equal(nrow(syn), 30)
  expect_equal(ncol(syn), 5)
})
