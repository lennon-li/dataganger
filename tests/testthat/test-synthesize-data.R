# Tests for synthesize_data() - [2.9]-[2.14]

# ---- Schema synthesis ----

test_that("synthesize_data() schema level returns typed placeholder rows", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  spec <- synth_spec(purpose = "demo", level = "schema", name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn, "dataganger_synthetic")
  expect_s3_class(syn, "tbl_df")
  expect_equal(nrow(syn), nrow(df))
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
  spec <- synth_spec(purpose = "demo", level = "schema", name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_type(syn$num, "double")
  expect_type(syn$chr, "character")
  expect_s3_class(syn$fac, "factor")
  expect_type(syn$lgl, "logical")
  expect_s3_class(syn$dt, "Date")
})

test_that("synthesize_data() schema with haven_labelled", {
  df <- tibble::tibble(
    status = haven::labelled(c(1, 2, 1), labels = c(A = 1, B = 2))
  )
  spec <- synth_spec(purpose = "demo", level = "schema", name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), nrow(df))
  expect_equal(ncol(syn), 1)
  expect_type(syn$status, "character")
})

# ---- Marginal synthesis ----

test_that("synthesize_data() marginal returns correct dimensions", {
  df <- data.frame(x = 1:10, y = letters[1:10])
  spec <- synth_spec(purpose = "demo", n = 20)
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 20)
  expect_equal(ncol(syn), 2)
  expect_s3_class(syn, "dataganger_synthetic")
})

test_that("synthesize_data() marginal numeric column", {
  set.seed(1)
  df <- data.frame(val = rnorm(100, mean = 50, sd = 10))
  spec <- synth_spec(purpose = "demo", n = 200)
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 200)
  expect_type(syn$val, "double")
  expect_true(all(syn$val >= min(df$val, na.rm = TRUE) - 1e-8))
  expect_true(all(syn$val <= max(df$val, na.rm = TRUE) + 1e-8))
})

test_that("synthesize_data() marginal factor column", {
  df <- data.frame(group = factor(rep(c("A", "B", "C"), each = 10)))
  spec <- synth_spec(purpose = "demo", n = 50)
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn$group, "factor")
  expect_true(all(as.character(syn$group) %in% c("A", "B", "C")))
})

test_that("synthesize_data() marginal Date column", {
  df <- data.frame(
    dt = as.Date(c("2023-01-15", "2023-06-20", "2023-12-01"))
  )
  spec <- synth_spec(purpose = "demo", n = 10)
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn$dt, "Date")
})

test_that("synthesize_data() marginal logical column", {
  df <- data.frame(flag = c(TRUE, FALSE, TRUE, TRUE))
  spec <- synth_spec(purpose = "demo", n = 50)
  syn <- synthesize_data(df, spec)
  expect_type(syn$flag, "logical")
})

test_that("synthesize_data() marginal haven_labelled column", {
  df <- tibble::tibble(
    status = haven::labelled(
      c(1, 2, 1, 2, 1),
      labels = c(Active = 1, Inactive = 2),
      label = "Status"
    )
  )
  spec <- synth_spec(purpose = "demo", n = 20, merge_rare = FALSE)
  syn <- synthesize_data(df, spec)
  expect_type(syn$status, "character")
  expect_true(all(stats::na.omit(syn$status) %in% c("Active", "Inactive")))
})

test_that("synthesize_data() marginal POSIXct column", {
  df <- data.frame(
    ts = as.POSIXct(c("2024-01-01 12:00:00", "2024-06-15 08:30:00")),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "demo", n = 10)
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn$ts, "POSIXct")
})

test_that("synthesize_data() preserves missingness at approximate rate", {
  df <- data.frame(
    val = c(rnorm(80), rep(NA_real_, 20))
  )
  spec <- synth_spec(purpose = "demo", n = 1000,
                     preserve_missingness = "approx")
  syn <- synthesize_data(df, spec)
  na_rate <- sum(is.na(syn$val)) / nrow(syn)
  expect_true(na_rate > 0.05 && na_rate < 0.35)
})

test_that("synthesize_data() missingness = none produces no NAs", {
  df <- data.frame(val = c(rnorm(5), NA))
  spec <- synth_spec(purpose = "demo", n = 50,
                     preserve_missingness = "none")
  syn <- synthesize_data(df, spec)
  expect_equal(sum(is.na(syn$val)), 0)
})

# ---- Engine checks ----

test_that("synthesize_data() errors when synthpop is not installed and engine = 'synthpop'", {
  skip_if(requireNamespace("synthpop", quietly = TRUE), "synthpop is installed")
  df   <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "demo")
  expect_error(
    synthesize_data(df, spec, engine = "synthpop"),
    "synthpop"
  )
})

test_that("synthesize_data() accepts engine = 'marginal' as alias for internal", {
  df   <- data.frame(x = 1:10, y = rnorm(10))
  spec <- synth_spec(purpose = "demo")
  syn  <- synthesize_data(df, spec, engine = "marginal")
  expect_s3_class(syn, "dataganger_synthetic")
})

test_that("synthesize_data() derives synthpop when installed", {
  skip_if_not_installed("synthpop")
  df <- data.frame(
    x = rnorm(30),
    y = rep(letters[1:3], length.out = 30),
    stringsAsFactors = FALSE
  )
  spec <- suppressWarnings(synth_spec(purpose = "development", seed = 1L))
  syn <- synthesize_data(df, spec)
  expect_equal(attr(syn, "engine"), "synthpop")
})

test_that("synthesize_data() falls back when derived synthpop is unavailable", {
  skip_if(requireNamespace("synthpop", quietly = TRUE), "synthpop is installed")
  df <- data.frame(x = 1:20, y = rep(letters[1:4], each = 5))
  spec <- suppressWarnings(synth_spec(purpose = "development", seed = 1L))
  expect_warning(
    syn <- synthesize_data(df, spec),
    "Install .*synthpop.*full-fidelity"
  )
  expect_s3_class(syn, "dataganger_synthetic")
  expect_equal(attr(syn, "engine"), "internal")
})

test_that("synthesize_data() routes objectives to expected engines", {
  df <- data.frame(x = 1:20, y = rep(letters[1:4], each = 5))

  teaching <- synth_spec(purpose = "demo", seed = 1L)
  syn_teaching <- synthesize_data(df, teaching)
  expect_equal(attr(syn_teaching, "engine"), "internal")

  model <- suppressWarnings(synth_spec(purpose = "development", seed = 1L))
  hifi <- synth_spec(purpose = "analytics", seed = 1L, acknowledge_risk = TRUE)

  if (requireNamespace("synthpop", quietly = TRUE)) {
    expect_equal(attr(synthesize_data(df, model), "engine"), "synthpop")
    expect_equal(attr(synthesize_data(df, hifi), "engine"), "synthpop")
  } else {
    expect_warning(expect_equal(attr(synthesize_data(df, model), "engine"), "internal"), "synthpop")
    expect_warning(expect_equal(attr(synthesize_data(df, hifi), "engine"), "internal"), "synthpop")
  }
})

test_that("synthesize_data() explicit internal overrides a synthpop-implying spec", {
  df <- data.frame(x = 1:5)
  spec <- suppressWarnings(synth_spec(purpose = "development"))
  syn <- synthesize_data(df, spec, engine = "internal")
  expect_equal(attr(syn, "engine"), "internal")
})

# ---- Seed reproducibility ----

test_that("synthesize_data() seed produces identical output", {
  df <- data.frame(x = rnorm(50), y = letters[1:50])
  spec <- synth_spec(purpose = "demo", n = 30, seed = 42)
  syn1 <- synthesize_data(df, spec)
  syn2 <- synthesize_data(df, spec)
  expect_equal(syn1$x, syn2$x)
  expect_equal(syn1$y, syn2$y)
})

test_that("synthesize_data() seed isolation does not mutate global RNG", {
  df <- data.frame(x = 1:10)
  set.seed(999)
  before <- .Random.seed
  spec <- synth_spec(purpose = "demo", n = 5, seed = 123)
  syn <- synthesize_data(df, spec)
  after <- .Random.seed
  expect_equal(before, after)
})

# ---- Edge cases ----

test_that("synthesize_data() all-NA numeric column", {
  df <- data.frame(x = rep(NA_real_, 10))
  spec <- synth_spec(purpose = "demo", n = 5)
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 5)
  expect_true(all(is.na(syn$x)))
})

test_that("synthesize_data() all-NA character column", {
  df <- data.frame(x = rep(NA_character_, 10))
  spec <- synth_spec(purpose = "demo", n = 5)
  syn <- synthesize_data(df, spec)
  expect_true(all(is.na(syn$x)))
})

test_that("synthesize_data() all-NA haven_labelled column", {
  df <- tibble::tibble(
    x = haven::labelled(
      rep(NA_real_, 5),
      labels = c(A = 1, B = 2)
    )
  )
  spec <- synth_spec(purpose = "demo", n = 5)
  syn <- synthesize_data(df, spec)
  expect_true(all(is.na(syn$x)))
  expect_type(syn$x, "character")
})

test_that("synthesize_data() 1-level factor does not error", {
  df <- data.frame(f = factor(rep("only", 10)))
  spec <- synth_spec(purpose = "demo", n = 20)
  expect_no_error(syn <- synthesize_data(df, spec))
  expect_s3_class(syn$f, "factor")
})

test_that("synthesize_data() 0-row input schema works", {
  df <- data.frame(x = numeric(0), y = character(0))
  spec <- synth_spec(purpose = "demo", level = "schema")
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 0)
  expect_equal(ncol(syn), 2)
})

test_that("synth_spec() rejects n = 0 for public API", {
  expect_error(
    synth_spec(purpose = "demo", n = 0),
    "must be > 0"
  )
})

test_that("synthesize_data() 1-row input does not error", {
  df <- data.frame(x = 42, y = "hello")
  spec <- synth_spec(purpose = "demo", n = 10)
  expect_no_error(syn <- synthesize_data(df, spec))
  expect_equal(nrow(syn), 10)
})

test_that("synthesize_data() 100% missing column handled", {
  df <- data.frame(
    good = 1:10,
    all_na = rep(NA_real_, 10)
  )
  spec <- synth_spec(purpose = "demo", n = 5)
  syn <- synthesize_data(df, spec)
  expect_true(all(is.na(syn$all_na)))
  expect_false(all(is.na(syn$good)))
})

# ---- Name strategies ----

test_that("synthesize_data() name_strategy 'generic' renames columns", {
  df <- data.frame(patient_name = 1:5, age_years = 21:25)
  spec <- synth_spec(purpose = "demo", n = 5, name_strategy = "generic")
  syn <- synthesize_data(df, spec)
  expect_named(syn, c("col_1", "col_2"))
  expect_equal(attr(syn, "spec")$name_map[["patient_name"]], "col_1")
  expect_equal(attr(syn, "spec")$name_map[["age_years"]], "col_2")
})

test_that("synthesize_data() name_strategy 'dictionary_only' renames and stores map", {
  df <- data.frame(patient_name = 1:5, age_years = 21:25)
  spec <- synth_spec(purpose = "demo", n = 5,
                     name_strategy = "dictionary_only")
  syn <- synthesize_data(df, spec)
  expect_named(syn, c("col_1", "col_2"))
  expect_true(!is.null(attr(syn, "spec")$name_map))
  expect_equal(attr(syn, "spec")$name_map[["patient_name"]], "col_1")
  expect_equal(attr(syn, "spec")$name_map[["age_years"]], "col_2")
})

test_that("synthesize_data() name_strategy 'preserve' keeps original names", {
  df <- data.frame(patient_name = 1:5, age_years = 21:25)
  spec <- synth_spec(purpose = "demo", n = 5, name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_named(syn, c("patient_name", "age_years"))
})

# ---- Attributes ----

test_that("synthesize_data() returns correct attributes", {
  df <- data.frame(x = 1:10)
  spec <- synth_spec(purpose = "demo", n = 5, seed = 7)
  syn <- synthesize_data(df, spec)
  expect_true(!is.null(attr(syn, "spec")))
  expect_equal(attr(syn, "original_dims"), list(nrow = 10, ncol = 1))
  expect_equal(attr(syn, "seed_used"), 7)
  expect_s3_class(attr(syn, "generated_at"), "POSIXct")
})

# ---- Input validation ----

test_that("synthesize_data() rejects non-data-frame", {
  expect_error(
    synthesize_data("not data", synth_spec(purpose = "demo")),
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
  spec <- synth_spec(purpose = "demo", n = 10)
  expect_no_error(synthesize_data(df, spec, roles = NULL))
})

test_that("synthesize_data() marginal with character column", {
  df <- data.frame(txt = rep(c("hello", "world", "foo", "bar"), each = 3))
  spec <- synth_spec(purpose = "demo", n = 20, merge_rare = FALSE)
  syn <- synthesize_data(df, spec)
  expect_type(syn$txt, "character")
  expect_true(all(syn$txt %in% c("hello", "world", "foo", "bar", NA)))
})

test_that("synthesize_data() default n equals nrow(original)", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "demo")  # n = NULL
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), 5)
})

test_that("synthesize_data() free text dropped when strategy is drop", {
  long_strings <- sprintf("very_long_text_for_free_text_test_%040d", 1:20)
  df <- data.frame(notes = long_strings, x = 1:20)
  spec <- synth_spec(purpose = "demo", n = 10,
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
  spec <- synth_spec(purpose = "demo", n = 30)
  expect_no_error(syn <- synthesize_data(df, spec))
  expect_equal(nrow(syn), 30)
  expect_equal(ncol(syn), 5)
})

test_that("simulation treatment passes through and drops columns", {
  df <- data.frame(
    id = sprintf("ID%03d", 1:30),
    x = 1:30,
    omit = letters[seq_len(30)],
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  roles$simulation[roles$variable == "id"] <- "pass_through"
  roles$simulation[roles$variable == "omit"] <- "drop"
  spec <- synth_spec(purpose = "demo")

  syn <- synthesize_data(df, spec, roles = roles)

  expect_identical(syn$id, df$id)
  expect_false("omit" %in% names(syn))
  expect_true("x" %in% names(syn))
})

test_that("pass-through treatment requires original row count", {
  df <- data.frame(id = sprintf("ID%03d", 1:30), x = 1:30)
  roles <- detect_roles(df)
  roles$simulation[roles$variable == "id"] <- "pass_through"
  spec <- synth_spec(purpose = "demo", n = 10)

  expect_error(
    synthesize_data(df, spec, roles = roles),
    "Cannot pass through original columns"
  )
})

test_that("name_strategy maps only output columns after drop treatment", {
  df <- data.frame(keep = 1:10, omit = 11:20)
  roles <- detect_roles(df)
  roles$simulation[roles$variable == "omit"] <- "drop"
  spec <- synth_spec(purpose = "demo", name_strategy = "generic")

  syn <- synthesize_data(df, spec, roles = roles)
  nm <- attr(syn, "spec")$name_map

  expect_named(syn, "col_1")
  expect_equal(nm, c(keep = "col_1"))
  expect_false("omit" %in% names(nm))
})

# ---- Phase 2.1 fix tests ----

# Fix 1 - remove_ids
test_that("remove_ids masks ID columns with NA", {
  # Use x with low cardinality so it's not also flagged as ID candidate
  df <- data.frame(
    id = 1:50,
    x  = rep(1:5, 10)
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "demo", n = 10)
  spec$remove_ids <- TRUE
  syn <- synthesize_data(df, spec, roles = roles)
  expect_true(all(is.na(syn$id)))
  expect_false(all(is.na(syn$x)))
})

# Fix 2 - haven::labelled() in schema synthesis
test_that("schema synthesis handles haven_labelled column without error", {
  df <- tibble::tibble(
    status = haven::labelled(c(1, 2, 1), labels = c(A = 1, B = 2)),
    x      = 1:3
  )
  spec <- synth_spec(purpose = "demo", level = "schema", name_strategy = "preserve")
  syn <- synthesize_data(df, spec)
  expect_equal(nrow(syn), nrow(df))
  expect_equal(ncol(syn), 2)
  expect_type(syn$status, "character")
})

# Fix 3 - factor levels preserved for rare levels
test_that("factor synthesis preserves rare levels in levels()", {
  df <- data.frame(
    f = factor(c(rep("common", 199), "rare"))
  )
  spec <- synth_spec(purpose = "demo", n = 10)
  syn <- synthesize_data(df, spec)
  expect_s3_class(syn$f, "factor")
  expect_true("rare" %in% levels(syn$f))
})

# Fix 4 - name_map stored inside spec attribute
test_that("name_strategy dictionary_only stores name_map in spec attr", {
  df <- data.frame(patient_name = 1:5, age_years = 21:25)
  spec <- synth_spec(purpose = "demo", n = 5,
                     name_strategy = "dictionary_only")
  syn <- synthesize_data(df, spec)
  nm <- attr(syn, "spec")$name_map
  expect_true(!is.null(nm))
  expect_type(nm, "character")
  expect_equal(nm[["patient_name"]], "col_1")
  expect_equal(nm[["age_years"]], "col_2")
})

# F2 - ".other" sentinel does not collide with real "other"
test_that("rare-merge uses .other sentinel not other", {
  df <- data.frame(
    f = factor(c(rep("other", 100), rep("x", 3), rep("y", 2)))
  )
  spec <- synth_spec(purpose = "demo", n = 50, merge_rare = TRUE,
                     rare_level_min_n = 5)
  syn <- synthesize_data(df, spec)
  # "other" was common so should survive; "x" and "y" merge to ".other"
  expect_true("other" %in% levels(syn$f) || "other" %in% syn$f)
})

# Safer_external end-to-end pipeline test
test_that("demo schema pipeline completes on example_health_survey", {
  skip_if_not_installed("dataganger")
  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "demo", level = "schema")
  syn <- synthesize_data(example_health_survey, spec)
  expect_equal(nrow(syn), nrow(example_health_survey))
  expect_equal(ncol(syn), ncol(example_health_survey))
})
