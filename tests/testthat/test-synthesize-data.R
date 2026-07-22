
# Tests for synthesize_data() - [2.9]-[2.14]

synthesize_data <- dataganger::synthesize_data
detect_roles <- dataganger::detect_roles
synth_spec <- dataganger::synth_spec

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

test_that("synthesize_data() jitters zero-IQR numeric columns with nonconstant outliers", {
  original <- data.frame(
    salary = c(rep(100, 55), 150, 200, 250, 300)
  )
  roles <- detect_roles(original)
  roles$identifies <- "none"
  roles$sensitive <- FALSE
  roles$disclosure_role <- "none"
  # Pin the internal engine: synth_numeric jitter is internal-engine behavior,
  # and the single-column fixture cannot be synthesized by synthpop at all.
  spec <- synth_spec(purpose = "development", seed = 22, n = nrow(original),
                     engine = "internal")

  syn <- synthesize_data(original, spec, roles = roles)

  exact_share <- mean(syn$salary %in% original$salary)
  non_modal_originals <- setdiff(unique(original$salary), 100)
  expect_lt(exact_share, 1)
  expect_false(all(non_modal_originals %in% syn$salary))
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
  skip_if_no_synthpop()
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

  if (!requireNamespace("synthpop", quietly = TRUE)) {
    # synthpop truly unavailable: derived synthpop warns and falls back
    expect_warning(expect_equal(attr(synthesize_data(df, model), "engine"), "internal"), "synthpop")
    expect_warning(expect_equal(attr(synthesize_data(df, hifi), "engine"), "internal"), "synthpop")
  } else if (isTRUE(getOption("dataganger.disable_synthpop", FALSE))) {
    # synthpop installed but disabled via option: silent route to internal
    expect_equal(attr(synthesize_data(df, model), "engine"), "internal")
    expect_equal(attr(synthesize_data(df, hifi), "engine"), "internal")
  } else {
    expect_equal(attr(synthesize_data(df, model), "engine"), "synthpop")
    expect_equal(attr(synthesize_data(df, hifi), "engine"), "synthpop")
  }
})

test_that("synthesize_data() explicit internal overrides a synthpop-implying spec", {
  df <- data.frame(x = 1:5)
  spec <- suppressWarnings(synth_spec(purpose = "development"))
  syn <- synthesize_data(df, spec, engine = "internal")
  expect_equal(attr(syn, "engine"), "internal")
})

test_that("synthesize_data() explicit auto remains objective-derived", {
  df <- data.frame(x = 1:20, y = rep(letters[1:4], each = 5))
  withr::local_options(list(dataganger.disable_synthpop = FALSE))
  demo_spec <- synth_spec(purpose = "demo", engine = "auto", seed = 1L)
  expect_equal(attr(synthesize_data(df, demo_spec), "engine"), "internal")
  expect_equal(attr(synthesize_data(df, demo_spec, engine = "auto"), "engine"), "internal")
  dev_spec <- suppressWarnings(synth_spec(purpose = "development", engine = "auto", seed = 1L))
  if (requireNamespace("synthpop", quietly = TRUE)) {
    expect_equal(attr(synthesize_data(df, dev_spec), "engine"), "synthpop")
  } else {
    expect_warning(expect_equal(attr(synthesize_data(df, dev_spec), "engine"), "internal"), "synthpop")
  }
})

test_that("synthesize_data() disable_synthpop is honored under auto", {
  skip_if_no_synthpop()
  df <- data.frame(x = 1:20, y = rep(letters[1:4], each = 5))
  withr::local_options(list(dataganger.disable_synthpop = TRUE))
  spec <- suppressWarnings(synth_spec(purpose = "development", engine = "auto", seed = 1L))
  syn <- synthesize_data(df, spec)
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

test_that("free_text_strategy defaults to categorical, not drop", {
  spec <- synth_spec(purpose = "demo")
  expect_equal(spec$free_text_strategy, "categorical")
})

test_that("synthesize_data() free text is synthesized as categorical by default", {
  set.seed(1)
  # Almost every note is unique; a handful repeat often enough to clear
  # rare_level_min_n (default 5) and should survive rare-level collapsing.
  common_note <- "Routine follow-up, no concerns to report at this visit."
  unique_notes <- sprintf(
    "Patient reports symptom variant number %d during today's visit.", 1:100
  )
  notes <- c(rep(common_note, 10), unique_notes)
  df <- data.frame(notes = notes, x = seq_along(notes))
  spec <- synth_spec(purpose = "demo", n = 200)

  syn <- synthesize_data(df, spec)

  expect_type(syn$notes, "character")
  expect_false(all(is.na(syn$notes)))
  # Every near-unique note collapses to ".other"; none reappear verbatim.
  expect_false(any(unique_notes %in% syn$notes))
  # The note repeated often enough (>= rare_level_min_n) is allowed to recur.
  expect_true(common_note %in% syn$notes)
  expect_true(all(syn$notes %in% c(common_note, ".other")))
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
    group = rep(c("A", "B", "C"), length.out = 30),
    x = 1:30,
    omit = letters[seq_len(30)],
    stringsAsFactors = FALSE
  )
  roles <- dataganger:::dg_sync_roles_axes(detect_roles(df))
  roles$simulation[roles$variable == "group"] <- "pass_through"
  roles$simulation[roles$variable == "omit"] <- "drop"
  roles$identifies[roles$variable == "patient_id"] <- "direct"
  roles$identifies[roles$variable %in% c("age_band", "region")] <- "combination"
  spec <- synth_spec(purpose = "demo")

  syn <- synthesize_data(df, spec, roles = roles)

  expect_identical(syn$group, df$group)
  expect_false("omit" %in% names(syn))
  expect_true("x" %in% names(syn))
})

test_that("pass-through treatment falls back gracefully when row count differs", {
  df <- data.frame(grp = rep(c("a", "b", "c"), 10L), x = 1:30)
  roles <- detect_roles(df)
  roles$simulation[roles$variable == "grp"] <- "pass_through"
  spec <- synth_spec(purpose = "demo", n = 10)

  # Should warn but NOT abort; synthesis completes at the requested row count.
  expect_warning(
    syn <- synthesize_data(df, spec, roles = roles),
    "Pass-through columns"
  )
  expect_equal(nrow(syn), 10L)
  expect_true("x" %in% names(syn))
})

test_that("simulation treatment scrambles an alphanumeric ID column", {
  set.seed(1)
  df <- data.frame(
    order_id = sprintf("OR-%04d-%02d", 1:30, sample(1:99, 30, TRUE)),
    x = 1:30,
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  expect_equal(roles$simulation[roles$variable == "order_id"], "scramble")
  spec <- synth_spec(purpose = "demo", engine = "internal")

  syn <- synthesize_data(df, spec, roles = roles, engine = "internal")

  expect_true("order_id" %in% names(syn))
  expect_false(any(syn$order_id %in% df$order_id))
  expect_true(all(grepl("^..-....-..$", syn$order_id)))
})

test_that("scramble treatment falls back gracefully when row count differs", {
  set.seed(1)
  df <- data.frame(
    order_id = sprintf("OR-%04d-%02d", 1:30, sample(1:99, 30, TRUE)),
    x = 1:30,
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "demo", n = 10, engine = "internal")

  expect_warning(
    syn <- synthesize_data(df, spec, roles = roles, engine = "internal"),
    "Scrambled columns"
  )
  expect_equal(nrow(syn), 10L)
  expect_true("x" %in% names(syn))
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


test_that("synthesize_data() handles roles missing one column", {
  df <- data.frame(id = 1:20, x = rep(1:5, 4), y = rep(letters[1:2], 10), stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  roles <- roles[roles$variable != "y", , drop = FALSE]
  spec <- synth_spec(purpose = "demo", n = 10)
  # id is an alphanumeric ID (default simulation "scramble"); the row-count
  # change (20 -> 10) makes scramble fall back to plain synthesis with a
  # warning, which is expected and irrelevant to this test.
  expect_no_error(syn <- suppressWarnings(synthesize_data(df, spec, roles = roles)))
  expect_s3_class(syn, "dataganger_synthetic")
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
  roles$disclosure_role[roles$variable == "x"] <- "none"
  spec <- synth_spec(purpose = "demo", n = 10)
  spec$remove_ids <- TRUE
  # "id" is an alphanumeric ID with a default "scramble" simulation, which
  # exempts it from enforce_kanon's drop -- but remove_ids already masked its
  # values to NA in synthesize_marginal, so it stays present and fully NA
  # rather than being dropped as a column. The row-count change (50 -> 10)
  # also makes scramble fall back to plain synthesis with a warning, which
  # is expected and irrelevant here since the column is already NA-masked.
  syn <- suppressWarnings(synthesize_data(df, spec, roles = roles))
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


test_that("synthesize_data() generic naming still drops direct identifiers before renaming", {
  df <- data.frame(
    patient_id = sprintf("id%02d", 1:20),
    age_band = rep(c("20s", "30s", "40s", "50s"), each = 5),
    region = rep(c("north", "south"), each = 10),
    stringsAsFactors = FALSE
  )
  roles <- dataganger:::dg_sync_roles_axes(detect_roles(df))
  roles$disclosure_role[roles$variable == "patient_id"] <- "direct"
  roles$disclosure_role[roles$variable %in% c("age_band", "region")] <- "quasi"
  roles$identifies[roles$variable == "patient_id"] <- "direct"
  roles$identifies[roles$variable %in% c("age_band", "region")] <- "combination"
  # patient_id defaults to simulation = "scramble" as an alphanumeric ID,
  # which is an explicit keep-decision exempting it from the drop below.
  # Force an explicit "drop" decision to test that identifiers are still
  # dropped before renaming when that decision is made.
  roles$simulation[roles$variable == "patient_id"] <- "drop"
  spec <- synth_spec(purpose = "demo", n = 20, seed = 11, name_strategy = "generic")

  syn <- synthesize_data(df, spec, roles = roles, engine = "internal")
  nm <- attr(syn, "spec")$name_map
  kanon <- attr(syn, "kanon")

  expect_false("patient_id" %in% names(nm))
  expect_named(syn, c("col_1", "col_2"))
  expect_equal(unname(nm[c("age_band", "region")]), c("col_1", "col_2"))
  expect_true(length(kanon$qi_cols) > 0L)
  expect_false(any(grepl("patient", names(syn), ignore.case = TRUE)))
})

# ---- Character-stored date/time synthesis ----

test_that("character-stored ISO date strings are synthesized as dates, not resampled verbatim", {
  set.seed(1)
  df <- data.frame(
    event_date = format(as.Date("2020-01-01") + sample(0:364, 100, TRUE), "%Y-%m-%d"),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  expect_equal(roles$recommended_role[roles$variable == "event_date"], "date")

  spec <- synth_spec(purpose = "demo", n = 100, seed = 2, coarsen_dates = FALSE)
  syn <- synthesize_data(df, spec, roles = roles, engine = "internal")

  # Format is preserved (still "YYYY-MM-DD" strings, not a Date object or a
  # different pattern).
  expect_type(syn$event_date, "character")
  expect_true(all(grepl("^\\d{4}-\\d{2}-\\d{2}$", syn$event_date)))
  # Values fall within the observed range rather than being copied verbatim.
  parsed <- as.Date(syn$event_date)
  expect_true(all(parsed >= as.Date("2020-01-01") & parsed <= as.Date("2020-12-30")))
  # Not simply the original column reshuffled.
  expect_false(identical(sort(syn$event_date), sort(df$event_date)))
})

test_that("character-stored date+time strings preserve both the date range and the time-of-day format", {
  set.seed(3)
  df <- data.frame(
    visit = sprintf(
      "%s %02d:%02d %s",
      format(as.Date("2020-01-01") + sample(0:29, 100, TRUE), "%m/%d/%Y"),
      sample(1:12, 100, TRUE), sample(0:59, 100, TRUE),
      sample(c("AM", "PM"), 100, TRUE)
    ),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  expect_equal(roles$recommended_role[roles$variable == "visit"], "date")

  spec <- synth_spec(purpose = "demo", n = 100, seed = 4, coarsen_dates = FALSE)
  syn <- synthesize_data(df, spec, roles = roles, engine = "internal")

  expect_true(all(grepl("^\\d{2}/\\d{2}/\\d{4} \\d{2}:\\d{2} (AM|PM)$", syn$visit)))
  # The time-of-day component varies rather than collapsing to midnight
  # (which is what blanket coarsen-to-day would otherwise do).
  times <- sub("^.* (\\d{2}:\\d{2} (AM|PM))$", "\\1", syn$visit)
  expect_gt(length(unique(times)), 1L)
})

test_that("a bare time-of-day column (no date part) is synthesized and stays time-only", {
  set.seed(5)
  df <- data.frame(
    check_in = sprintf("%02d:%02d", sample(6:20, 100, TRUE), sample(0:59, 100, TRUE)),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  expect_equal(roles$recommended_role[roles$variable == "check_in"], "date")

  spec <- synth_spec(purpose = "demo", n = 100, seed = 6, coarsen_dates = FALSE)
  syn <- synthesize_data(df, spec, roles = roles, engine = "internal")

  expect_true(all(grepl("^\\d{2}:\\d{2}$", syn$check_in)))
  # No date leaked into the output.
  expect_false(any(grepl("[-/]", syn$check_in)))
  hours <- as.integer(substr(syn$check_in, 1, 2))
  expect_true(all(hours >= 6 & hours <= 20))
})

test_that("character-stored dates preserve the original NA rate", {
  set.seed(7)
  x <- format(as.Date("2020-01-01") + sample(0:364, 200, TRUE), "%m/%d/%Y")
  x[sample(seq_along(x), 40)] <- NA
  df <- data.frame(sched = x, stringsAsFactors = FALSE)
  roles <- detect_roles(df)

  spec <- synth_spec(purpose = "demo", n = 200, seed = 8, coarsen_dates = FALSE)
  syn <- synthesize_data(df, spec, roles = roles, engine = "internal")

  expect_true(any(is.na(syn$sched)))
  expect_true(all(grepl("^\\d{2}/\\d{2}/\\d{4}$", stats::na.omit(syn$sched))))
})
