test_that("spec_to_synthpop_args() maps n, seed, exclusions, and smoothing", {
  df <- data.frame(
    record_id = paste0("ID-", 1:25),
    notes = sprintf("this is long free text value number %02d", 1:25),
    # continuous (non-integer) but not all-distinct, so it is not flagged an
    # ID candidate (distinct_ratio < 0.95) and survives to the smoothing step
    score = rep(c(1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8, 9.9, 10.1, 11.2, 12.3),
                length.out = 25),
    bounded = rep(1:5, length.out = 25),
    group = rep(letters[1:5], length.out = 25),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "demo", n = 10L, seed = 42L)
  args <- spec_to_synthpop_args(spec, roles, df)

  expect_equal(args$k, 10L)
  expect_equal(args$seed, 42L)
  expect_false("record_id" %in% names(args$data))
  expect_false("notes" %in% names(args$data))
  expect_true("score" %in% names(args$smoothing))
  expect_equal(args$smoothing[["score"]], "density")
  expect_false("bounded" %in% names(args$smoothing))
})

test_that("spec_to_synthpop_args() omits smoothing for pure-integer data", {
  df <- data.frame(x = 1:25, y = rep(1:5, length.out = 25))
  spec <- synth_spec(purpose = "demo")
  args <- spec_to_synthpop_args(spec, roles = NULL, data = df)
  expect_null(args$smoothing)
})

test_that("synthpop_visit_sequence() tiers quasi/none/NA ahead of sensitive", {
  roles <- data.frame(
    variable = c("a", "b", "c", "d", "e"),
    disclosure_role = c("sensitive", "quasi", "none", NA_character_, "sensitive"),
    stringsAsFactors = FALSE
  )
  expect_equal(
    synthpop_visit_sequence(c("a", "b", "c", "d", "e"), roles),
    c("b", "c", "d", "a", "e")
  )
})

test_that("synthpop_visit_sequence() preserves original order within each tier", {
  roles <- data.frame(
    variable = c("s1", "q1", "s2", "q2", "q3"),
    disclosure_role = c("sensitive", "quasi", "sensitive", "quasi", "none"),
    stringsAsFactors = FALSE
  )
  # Non-sensitive (q1, q2, q3) keep their relative order, then sensitive
  # (s1, s2) keep theirs -- a stable sort, not a re-sort by role name.
  expect_equal(
    synthpop_visit_sequence(c("s1", "q1", "s2", "q2", "q3"), roles),
    c("q1", "q2", "q3", "s1", "s2")
  )
})

test_that("synthpop_visit_sequence() falls back to input order without roles", {
  work_names <- c("z", "a", "m")
  expect_equal(synthpop_visit_sequence(work_names, roles = NULL), work_names)

  roles_no_disclosure <- data.frame(variable = work_names, recommended_role = "categorical")
  expect_equal(synthpop_visit_sequence(work_names, roles_no_disclosure), work_names)

  roles_no_variable <- data.frame(disclosure_role = c("sensitive", "quasi", "none"))
  expect_equal(synthpop_visit_sequence(work_names, roles_no_variable), work_names)
})

test_that("synthpop_visit_sequence() is a no-op reorder when no column is sensitive", {
  work_names <- c("a", "b", "c")
  roles <- data.frame(
    variable = work_names,
    disclosure_role = c("quasi", "none", NA_character_),
    stringsAsFactors = FALSE
  )
  expect_equal(synthpop_visit_sequence(work_names, roles), work_names)
})

test_that("spec_to_synthpop_args() sets a role-aware visit.sequence", {
  df <- data.frame(a = 1:20, b = 1:20, c = 1:20)
  roles <- data.frame(
    variable = c("a", "b", "c"),
    disclosure_role = c("sensitive", "quasi", "none"),
    recommended_role = "categorical",
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "demo")
  args <- spec_to_synthpop_args(spec, roles, df)
  expect_equal(args$visit.sequence, c("b", "c", "a"))
})

test_that("spec_to_synthpop_args() keeps raw column order without disclosure_role", {
  df <- data.frame(a = 1:20, b = 1:20, c = 1:20)
  spec <- synth_spec(purpose = "demo")
  args <- spec_to_synthpop_args(spec, roles = NULL, data = df)
  expect_equal(args$visit.sequence, names(df))
})

test_that("synthesize_synthpop() never lets a sensitive column predict a quasi/none column", {
  skip_if_no_synthpop()
  n <- 60
  df <- data.frame(
    age       = rep(1:6, length.out = n),
    diagnosis = rep(letters[1:3], length.out = n),
    province  = rep(c("ON", "BC", "QC"), length.out = n),
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = c("age", "diagnosis", "province"),
    disclosure_role = c("quasi", "sensitive", "quasi"),
    recommended_role = "categorical",
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "demo", seed = 1L)
  syn_args <- spec_to_synthpop_args(spec, roles, df)
  result <- do.call(synthpop::syn, syn_args)

  quasi_cols <- c("age", "province")
  sensitive_cols <- "diagnosis"
  # predictor.matrix[target, predictor]: a sensitive column must never be a
  # predictor of a quasi/none column, whatever dimname order synthpop reports
  # the matrix in.
  submatrix <- result$predictor.matrix[quasi_cols, sensitive_cols, drop = FALSE]
  expect_true(
    all(submatrix == 0),
    info = paste(
      "predictor.matrix[quasi/none, sensitive] must be all zero",
      "(no sensitive column may predict a quasi/none column):",
      paste(capture.output(print(submatrix)), collapse = "\n")
    )
  )
})

test_that("synthesize_synthpop() returns a tibble with same columns", {
  skip_if_no_synthpop()
  df   <- data.frame(x = 1:20, y = letters[rep(1:4, 5)], stringsAsFactors = FALSE)
  spec <- synth_spec(purpose = "demo", seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_s3_class(syn, "tbl_df")
  expect_named(syn, names(df))
})

test_that("synthesize_synthpop() respects n rows via spec$n", {
  skip_if_no_synthpop()
  df   <- data.frame(x = 1:30, y = rnorm(30))
  spec <- synth_spec(purpose = "demo", n = 10L, seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_equal(nrow(syn), 10L)
})

test_that("synthesize_synthpop() excludes ID candidate columns", {
  skip_if_no_synthpop()
  df <- data.frame(
    record_id = paste0("ID-", 1:25),
    score     = rep(1:5, each = 5),
    group     = rep(letters[1:5], each = 5),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "demo", seed = 1L)
  syn   <- synthesize_synthpop(df, spec, roles = roles)
  expect_false("record_id" %in% names(syn))
  expect_true("score" %in% names(syn))
  expect_true("group" %in% names(syn))
})

test_that("synthesize_synthpop() seed produces reproducible output", {
  skip_if_no_synthpop()
  df   <- data.frame(x = rnorm(20), y = rnorm(20))
  spec <- synth_spec(purpose = "demo", seed = 42L)
  syn1 <- synthesize_synthpop(df, spec)
  syn2 <- synthesize_synthpop(df, spec)
  expect_equal(syn1$x, syn2$x)
})

test_that("seeded scramble stays deterministic on the synthpop path", {
  skip_if_no_synthpop()
  df <- data.frame(
    order_id = sprintf("OR-%04d-%02d", 1:30, 10:39),
    x = rnorm(30),
    y = rnorm(30),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "demo", engine = "synthpop", seed = 42L)

  syn1 <- synthesize_data(df, spec, roles = roles)
  stats::runif(128)
  syn2 <- synthesize_data(df, spec, roles = roles)

  expect_identical(syn1$order_id, syn2$order_id)
})

test_that("synthesize_synthpop() aborts when all columns are excluded", {
  skip_if_no_synthpop()
  df    <- data.frame(id = paste0("X-", 1:25), stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "demo")
  expect_error(synthesize_synthpop(df, spec, roles = roles), "No synthesizable columns")
})

test_that("synthpop_bridge_cols() identifies high-cardinality char columns", {
  withr::local_locale(c(LC_TIME = "C"))
  df <- data.frame(
    date_str = format(as.Date("2020-01-01") + 1:50, "%b %e, %Y"), # date role
    big_cat  = sprintf("cat_%03d", rep(1:30, length.out = 50)),     # 30 distinct, letter+digit shape -> alphanumeric ID
    small_cat = rep(letters[1:5], each = 10),                        # 5 distinct, OK
    score     = rnorm(50),
    stringsAsFactors = FALSE
  )
  roles  <- detect_roles(df)
  bridge <- synthpop_bridge_cols(roles, df)
  expect_true("date_str"  %in% bridge)
  # big_cat's consistent letter+digit shape now gets recommended_role
  # "alphanumeric ID", so it is truly excluded (handled by
  # apply_simulation_treatment's scramble) rather than bridged.
  expect_false("big_cat"  %in% bridge)
  expect_true("big_cat"   %in% synthpop_role_excluded_cols(roles))
  expect_false("small_cat" %in% bridge)
  expect_false("score"     %in% bridge)
})

test_that("synthpop native dates use the coarsened bridge", {
  skip_if_no_synthpop()
  df <- data.frame(
    day = rep(as.Date("2020-01-15") + 0:9, 10),
    x = rep(1:10, 10),
    grp = rep(c("a", "b"), 50)
  )
  roles <- detect_roles(df)
  roles$disclosure_role <- "none"
  roles$identifies <- "neither"
  roles$simulation <- "synthesize"
  spec <- synth_spec("development", seed = 42L, engine = "synthpop",
                     coarsen_dates = TRUE)
  syn <- synthesize_data(df, spec, roles = roles)
  expect_s3_class(syn$day, "Date")
  expect_equal(unique(format(syn$day, "%d")), "01")
  expect_true("day" %in% synthpop_bridge_cols(roles, df))
})

test_that("a POSIXct bridge with one CART column reports internal fallback", {
  skip_if_no_synthpop()
  df <- data.frame(
    stamp = as.POSIXct("2020-01-01 12:00:00", tz = "UTC") + seq(0, 19) * 86400,
    x = seq_len(20)
  )
  roles <- detect_roles(df)
  roles$disclosure_role <- "none"
  roles$identifies <- "neither"
  roles$simulation <- "synthesize"
  spec <- synth_spec("demo", seed = 7L, n = 20L, engine = "synthpop",
                     coarsen_dates = TRUE)
  expect_warning(
    syn <- synthesize_data(df, spec, roles = roles),
    "Fewer than two synthpop CART columns"
  )
  expect_identical(attr(syn, "engine"), "internal")
  expect_s3_class(syn$stamp, "POSIXct")
})

test_that("synthpop_bridge_cols() also catches high-cardinality factor columns", {
  # The CART-hang mechanism (2^(k-1) factor splits for a factor predictor) is
  # not specific to character storage: an R factor column with the same
  # cardinality poses the same hang risk, but `!is.character(x)` previously
  # skipped it entirely. Column name is generic (not ID-pattern-like, not
  # digit-suffixed) so role detection lands on "unknown" rather than
  # "alphanumeric ID", isolating the cardinality guard itself.
  words <- c(
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
    "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa",
    "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey",
    "xray", "yankee", "zulu"
  )
  df <- data.frame(
    region = factor(rep(words, length.out = 200)),
    score  = rnorm(200),
    stringsAsFactors = FALSE
  )
  roles  <- detect_roles(df)
  expect_equal(roles$recommended_role[roles$variable == "region"], "unknown")
  bridge <- synthpop_bridge_cols(roles, df)
  expect_true("region" %in% bridge)
})

test_that("synthesize_synthpop() stitches bridge columns back into original order", {
  skip_if_no_synthpop()
  df <- data.frame(
    id      = paste0("ID-", 1:25),                            # excluded (ID)
    d_str   = format(as.Date("2020-01-01") + 1:25, "%Y-%m-%d"), # bridge
    score   = rep(1:5, each = 5),
    group   = rep(letters[1:5], each = 5),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "demo", n = 10L, seed = 1L)
  syn   <- synthesize_synthpop(df, spec, roles = roles)
  # id excluded, d_str (date bridge) stitched back, score + group in synthpop
  expect_false("id"    %in% names(syn))
  expect_true( "d_str" %in% names(syn))
  expect_true( "score" %in% names(syn))
  expect_true( "group" %in% names(syn))
  # column order mirrors original (minus excluded id)
  expect_equal(names(syn), c("d_str", "score", "group"))
})

# Regression: Bug 5 -- CUSUM-shaped data (char-stored date + high-cardinality
# char predictor) used to hang synthpop's CART. Verify completion < 30 s.
test_that("synthesize_data() with high-cardinality char date column completes without hang", {
  skip_if_no_synthpop()
  withr::local_locale(c(LC_TIME = "C"))
  set.seed(42)
  n <- 500L
  df <- data.frame(
    case_id   = sprintf("CASE-%05d", 1:n),         # ID -> excluded
    date_str  = format(seq.Date(as.Date("2019-01-01"), by = "day",
                                length.out = n), "%b %e, %Y"),  # date bridge
    month     = rep(month.abb, length.out = n),    # 12 distinct char
    region    = rep(LETTERS[1:6], length.out = n), # 6 distinct char
    count     = sample(1:10, n, replace = TRUE),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec  <- suppressWarnings(synth_spec("development", n = 50L, seed = 1L))
  t0    <- proc.time()[["elapsed"]]
  syn   <- synthesize_data(df, spec, roles = roles)
  elapsed <- proc.time()[["elapsed"]] - t0
  expect_lt(elapsed, 30, label = "synthesis should complete in under 30 seconds")
  expect_s3_class(syn, "dataganger_synthetic")
  expect_equal(nrow(syn), 50L)
})

test_that("synthesize_data() derives roles for synthpop so high-cardinality IDs don't stall it", {
  # Regression: with roles = NULL, an ID / free-text column was passed to
  # synthpop, whose sequential CART grinds forever on a high-cardinality
  # categorical. synthesize_data() must derive roles and exclude such columns.
  skip_if_no_synthpop()
  df <- data.frame(
    rec_id = sprintf("R%04d", 1:60),   # 60 unique -> ID candidate, would stall CART
    age    = round(rnorm(60, 50, 10)),
    grp    = factor(sample(c("a", "b", "c"), 60, TRUE)),
    stringsAsFactors = FALSE
  )
  spec <- suppressWarnings(synth_spec("development", seed = 1L))
  syn <- synthesize_data(df, spec)          # no roles passed
  expect_equal(attr(syn, "engine"), "synthpop")
  expect_s3_class(syn, "dataganger_synthetic")
  expect_equal(nrow(syn), 60L)
})

test_that("labelled columns with a rare level survive the synthpop path", {
  skip_if_no_synthpop()

  # Regression: synthpop's sequential CART calls t() on the response, and
  # t.haven_labelled() does not exist. Under label_strategy = "preserve" the
  # column previously reached syn() still classed as haven_labelled and the
  # call hard-errored with "`t.haven_labelled()` not supported".
  #
  # The distribution matters: a balanced labelled column did not trigger it,
  # so the fixture below is deliberately skewed with a level seen twice in
  # 300 rows. That is the normal shape of a coded survey or clinical variable,
  # and "analytics" defaults to label_strategy = "preserve", so this was
  # reachable with default settings on real data.
  n <- 300L
  df <- data.frame(
    low = rep(c("A", "B", "C"), length.out = n),
    num = seq_len(n),
    stringsAsFactors = FALSE
  )
  df$coded <- haven::labelled(
    c(rep(1, 290L), rep(2, 8L), 3, 3),
    labels = c(Alpha = 1, Bravo = 2, Charlie = 3)
  )

  roles <- detect_roles(df)
  roles$user_role[roles$variable %in% c("low", "coded")] <- "categorical"
  roles$user_role[roles$variable == "num"] <- "numeric"
  roles$label_strategy[roles$variable %in% c("low", "coded")] <- "preserve"

  for (purpose in c("development", "analytics")) {
    spec <- synth_spec(
      purpose = purpose, seed = 1L,
      acknowledge_risk = identical(purpose, "analytics")
    )
    syn <- suppressWarnings(synthesize_data(df, spec, roles = roles))

    expect_equal(nrow(syn), n, info = purpose)

    observed <- sort(unique(as.character(syn$coded)))
    expect_setequal(observed, c("Alpha", "Bravo", "Charlie"))
  }
})

# ---- One synthesizable column after exclusions -------------------------

# A frame whose only surviving column after ID/free-text/high-cardinality
# exclusion is `score`; synthpop::syn() needs at least two columns.
one_synthesizable_col_df <- function() {
  data.frame(
    record_id = paste0("X-", 1:25),
    score     = rep(c(1.1, 2.2, 3.3, 4.4, 5.5), length.out = 25),
    stringsAsFactors = FALSE
  )
}

test_that("auto-derived synthpop falls back to internal on one synthesizable column", {
  skip_if_no_synthpop()
  df    <- one_synthesizable_col_df()
  roles <- detect_roles(df)
  expect_equal(
    setdiff(names(df), synthpop_excluded_cols(roles, df)),
    "score"
  )

  spec <- suppressWarnings(synth_spec(purpose = "development", seed = 1L))
  expect_warning(
    syn <- synthesize_data(df, spec, roles = roles),
    "Only one synthesizable column"
  )
  expect_equal(attr(syn, "engine"), "internal")
  expect_s3_class(syn, "dataganger_synthetic")
  expect_equal(nrow(syn), nrow(df))
  expect_true("score" %in% names(syn))
})

test_that("explicit synthpop aborts clearly on one synthesizable column", {
  skip_if_no_synthpop()
  df    <- one_synthesizable_col_df()
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "demo", engine = "synthpop", seed = 1L)

  expect_error(
    synthesize_data(df, spec, roles = roles),
    "Only one synthesizable column"
  )
  # Not synthpop's own opaque message.
  expect_error(
    synthesize_data(df, spec, roles = roles),
    "at least two"
  )
  err <- tryCatch(synthesize_data(df, spec, roles = roles), error = identity)
  expect_false(grepl("Data should contain", conditionMessage(err), fixed = TRUE))
})

test_that("multi-column synthpop path is unchanged by the one-column guard", {
  skip_if_no_synthpop()
  df <- data.frame(
    record_id = paste0("X-", 1:40),
    score     = rep(c(1.1, 2.2, 3.3, 4.4, 5.5), length.out = 40),
    grp       = rep(letters[1:4], length.out = 40),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "demo", engine = "synthpop", seed = 1L)
  syn   <- synthesize_data(df, spec, roles = roles)
  expect_equal(attr(syn, "engine"), "synthpop")
  expect_equal(nrow(syn), nrow(df))
})
