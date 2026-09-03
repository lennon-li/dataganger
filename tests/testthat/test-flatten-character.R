# Direct tests for the categorical type contract in R/flatten-character.R:
# normalize_categorical_input() (input boundary), flatten_to_character()
# (output backstop) and restore_logical_columns() (logical carve-out).
#
# Engine-agnostic tests pin engine = "internal" on purpose: purpose =
# "development" routes to synthpop when synthpop is installed, so an unpinned
# spec would make the execution path depend on the local library.

# ---------------------------------------------------------------------------
# normalize_categorical_input()
# ---------------------------------------------------------------------------

test_that("normalize_categorical_input() converts factors to character", {
  data <- data.frame(g = factor(c("b", "a", "b")), stringsAsFactors = FALSE)

  out <- normalize_categorical_input(data)

  expect_type(out$g, "character")
  expect_equal(out$g, c("b", "a", "b"))
  expect_null(levels(out$g))
})

test_that("normalize_categorical_input() converts labelled to its labels", {
  data <- data.frame(id = 1:2)
  data$status <- haven::labelled(
    c(1, 2),
    labels = c(active = 1, retired = 2)
  )

  out <- normalize_categorical_input(data)

  expect_type(out$status, "character")
  expect_equal(out$status, c("active", "retired"))
})

test_that("normalize_categorical_input() leaves non-categorical types alone", {
  data <- data.frame(
    num  = c(1.5, 2.5),
    int  = 1:2,
    chr  = c("a", "b"),
    lgl  = c(TRUE, FALSE),
    date = as.Date(c("2020-01-01", "2020-01-02")),
    stringsAsFactors = FALSE
  )

  out <- normalize_categorical_input(data)

  expect_identical(out, data)
})

test_that("normalize_categorical_input() leaves list-columns untouched", {
  data <- data.frame(id = 1:2)
  data$payload <- list(1:2, 3:4)

  out <- normalize_categorical_input(data)

  expect_type(out$payload, "list")
  expect_identical(out$payload, data$payload)
})

test_that("normalize_categorical_input() preserves NA and empty strings", {
  data <- data.frame(g = factor(c("a", NA, "")), stringsAsFactors = FALSE)

  out <- normalize_categorical_input(data)

  expect_equal(out$g, c("a", NA, ""))
  expect_true(is.na(out$g[2]))
  expect_identical(out$g[3], "")
})

test_that("normalize_categorical_input() handles zero-row and zero-column input", {
  zero_rows <- data.frame(
    g = factor(character(0), levels = c("a", "b")),
    x = numeric(0)
  )

  out <- normalize_categorical_input(zero_rows)

  expect_equal(nrow(out), 0L)
  expect_type(out$g, "character")
  expect_type(out$x, "double")

  # No columns: the loop body never runs and the frame comes back unchanged.
  empty <- data.frame()
  expect_identical(normalize_categorical_input(empty), empty)
})

test_that("normalize_categorical_input() drops factor levels with zero rows", {
  # Documented and deliberate: an unused level is metadata, not an output
  # value, and character cannot carry it.
  data <- data.frame(
    g = factor(c("a", "a"), levels = c("a", "never_observed")),
    stringsAsFactors = FALSE
  )

  out <- normalize_categorical_input(data)

  expect_equal(sort(unique(out$g)), "a")
  expect_false("never_observed" %in% out$g)
})

# ---------------------------------------------------------------------------
# flatten_to_character()
# ---------------------------------------------------------------------------

test_that("flatten_to_character() flattens factors and labelled columns", {
  syn <- data.frame(
    g   = factor(c("x", "y")),
    num = c(1, 2),
    stringsAsFactors = FALSE
  )
  syn$lab <- haven::labelled(c(1, 2), labels = c(low = 1, high = 2))

  out <- flatten_to_character(syn)

  expect_type(out$g, "character")
  expect_equal(out$g, c("x", "y"))
  expect_type(out$lab, "character")
  expect_equal(out$lab, c("low", "high"))
  expect_type(out$num, "double")
})

test_that("flatten_to_character() preserves NA, empty strings and row order", {
  syn <- data.frame(g = factor(c("b", NA, "", "a")), stringsAsFactors = FALSE)

  out <- flatten_to_character(syn)

  expect_equal(out$g, c("b", NA, "", "a"))
})

test_that("flatten_to_character() preserves logicals and zero-row frames", {
  syn <- data.frame(
    flag = logical(0),
    g    = factor(character(0), levels = c("a", "b"))
  )

  out <- flatten_to_character(syn)

  expect_equal(nrow(out), 0L)
  expect_type(out$flag, "logical")
  expect_type(out$g, "character")
})

test_that("flatten_to_character() keeps class and attributes of the frame", {
  syn <- tibble::tibble(g = factor(c("a", "b")))
  attr(syn, "engine") <- "synthpop"

  out <- flatten_to_character(syn)

  expect_s3_class(out, "tbl_df")
  expect_identical(attr(out, "engine"), "synthpop")
})

# ---------------------------------------------------------------------------
# restore_logical_columns()
# ---------------------------------------------------------------------------

test_that("restore_logical_columns() restores a flattened character column", {
  original <- data.frame(flag = c(TRUE, FALSE, TRUE), n = 1:3)
  syn <- data.frame(
    flag = c("TRUE", "FALSE", "FALSE"),
    n    = 1:3,
    stringsAsFactors = FALSE
  )

  out <- restore_logical_columns(syn, original)

  expect_type(out$flag, "logical")
  expect_equal(out$flag, c(TRUE, FALSE, FALSE))
})

test_that("restore_logical_columns() restores a two-level factor column", {
  original <- data.frame(flag = c(TRUE, FALSE))
  syn <- data.frame(flag = factor(c("FALSE", "TRUE")))

  out <- restore_logical_columns(syn, original)

  expect_type(out$flag, "logical")
  expect_equal(out$flag, c(FALSE, TRUE))
})

test_that("restore_logical_columns() carries NA through as logical NA", {
  original <- data.frame(flag = c(TRUE, FALSE, NA))
  syn <- data.frame(
    flag = c("TRUE", NA, "FALSE"),
    stringsAsFactors = FALSE
  )

  out <- restore_logical_columns(syn, original)

  expect_type(out$flag, "logical")
  expect_equal(out$flag, c(TRUE, NA, FALSE))
})

test_that("restore_logical_columns() skips columns the original did not type as logical", {
  original <- data.frame(
    label = c("TRUE", "FALSE"),
    stringsAsFactors = FALSE
  )
  syn <- data.frame(label = c("TRUE", "FALSE"), stringsAsFactors = FALSE)

  out <- restore_logical_columns(syn, original)

  expect_type(out$label, "character")
  expect_equal(out$label, c("TRUE", "FALSE"))
})

test_that("restore_logical_columns() leaves an already-logical column untouched", {
  original <- data.frame(flag = c(TRUE, FALSE))
  syn <- data.frame(flag = c(FALSE, TRUE))

  out <- restore_logical_columns(syn, original)

  expect_identical(out$flag, c(FALSE, TRUE))
})

test_that("restore_logical_columns() refuses values that are not TRUE/FALSE", {
  original <- data.frame(flag = c(TRUE, FALSE))
  syn <- data.frame(flag = c("TRUE", "maybe"), stringsAsFactors = FALSE)

  out <- restore_logical_columns(syn, original)

  expect_type(out$flag, "character")
  expect_equal(out$flag, c("TRUE", "maybe"))
})

test_that("restore_logical_columns() ignores columns absent from the other frame", {
  original <- data.frame(flag = c(TRUE, FALSE), dropped = c(TRUE, TRUE))
  syn <- data.frame(
    flag  = c("TRUE", "FALSE"),
    extra = c("a", "b"),
    stringsAsFactors = FALSE
  )

  out <- restore_logical_columns(syn, original)

  expect_named(out, c("flag", "extra"))
  expect_type(out$flag, "logical")
  expect_type(out$extra, "character")
})

test_that("restore_logical_columns() handles a zero-row frame", {
  original <- data.frame(flag = logical(0))
  syn <- data.frame(flag = character(0), stringsAsFactors = FALSE)

  out <- restore_logical_columns(syn, original)

  expect_equal(nrow(out), 0L)
  expect_type(out$flag, "logical")
})

# ---------------------------------------------------------------------------
# End-to-end contract through synthesize_data()
# ---------------------------------------------------------------------------

test_that("synthesize_data() returns character for factor input on the internal engine", {
  data <- data.frame(
    g = factor(rep(c("a", "b"), each = 10)),
    x = seq_len(20),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "demo", seed = 42L)

  syn <- synthesize_data(data, spec, engine = "internal")

  expect_type(syn$g, "character")
  expect_false(is.factor(syn$g))
})

test_that("synthesize_data() preserves logical type on the internal engine", {
  data <- data.frame(
    flag = rep(c(TRUE, FALSE), each = 10),
    x    = seq_len(20)
  )
  spec <- synth_spec(purpose = "demo", seed = 42L)

  syn <- synthesize_data(data, spec, engine = "internal")

  expect_type(syn$flag, "logical")
  expect_equal(setdiff(syn$flag, c(TRUE, FALSE, NA)), logical(0))
})

test_that("synthpop output keeps logicals logical and categoricals character", {
  # synthpop models a logical column as a two-level factor. Without the
  # flatten + restore pair the same input would come back `logical` from the
  # internal engine and `character` from synthpop.
  skip_if_no_synthpop()

  data <- data.frame(
    flag  = rep(c(TRUE, FALSE), length.out = 30),
    group = factor(rep(c("a", "b", "c"), length.out = 30)),
    score = rep(c(1.5, 2.5, 3.5, 4.5, 5.5), length.out = 30),
    stringsAsFactors = FALSE
  )
  spec <- synth_spec(purpose = "demo", seed = 7L)

  syn <- synthesize_data(data, spec, engine = "synthpop")

  expect_identical(attr(syn, "engine"), "synthpop")
  expect_type(syn$flag, "logical")
  expect_equal(setdiff(syn$flag, c(TRUE, FALSE, NA)), logical(0))
  expect_type(syn$group, "character")
  expect_false(is.factor(syn$group))
  expect_equal(setdiff(syn$group, c("a", "b", "c", NA)), character(0))
})
