# synth_categorical() is the shared resampling path for categorical *and*
# free-text columns (synth_free_text() delegates to it), so its rare-level
# handling is a disclosure control, not just a fidelity knob.

test_that("rare levels are never drawn into the synthetic output", {
  set.seed(1)
  x <- c(rep("Hypertension", 40), rep("Diabetes", 20),
         "Wilson disease", "Fabry disease")
  syn <- synth_categorical(x, n = 500, rare_level_min_n = 5)

  expect_false("Wilson disease" %in% syn)
  expect_false("Fabry disease" %in% syn)
  expect_true(".other" %in% syn)
  # Common values are resampled verbatim -- this is resampling, not generation.
  expect_true(all(c("Hypertension", "Diabetes") %in% syn))
})

test_that("factor levels preserve merged rare values", {
  set.seed(1)
  x <- factor(c(rep("Hypertension", 40), rep("Diabetes", 20),
                "Wilson disease", "Fabry disease"))
  syn <- synth_categorical(x, n = 62, rare_level_min_n = 5)

  expect_s3_class(syn, "factor")
  expect_true("Wilson disease" %in% levels(syn))
  expect_true("Fabry disease" %in% levels(syn))
  expect_true(".other" %in% levels(syn))
  expect_true(all(c("Hypertension", "Diabetes") %in% levels(syn)))
})

test_that("levels the caller declared but never used are preserved", {
  set.seed(1)
  # An unused level is schema the user supplied, not a value observed in the
  # source, so the rare-value merge leaves it alone.
  x <- factor(c(rep("a", 20), rep("b", 20)), levels = c("a", "b", "c"))
  syn <- synth_categorical(x, n = 40, rare_level_min_n = 5)

  expect_true("c" %in% levels(syn))
  expect_equal(sum(syn == "c", na.rm = TRUE), 0L)
})

test_that("merge_rare = FALSE resamples rare values verbatim", {
  set.seed(1)
  x <- c(rep("common", 60), "singleton")
  syn <- synth_categorical(x, n = 4000, merge_rare = FALSE)

  # This is the analytics preset's behaviour: with merging off, a value seen
  # once in the source is eligible for the sampling pool and does appear.
  expect_true("singleton" %in% syn)
  expect_false(".other" %in% syn)
})

test_that("categorical sampling includes every pool level", {
  x <- c(rep("common", 100), "rare", "uncommon")

  for (seed in c(1, 10, 100)) {
    set.seed(seed)
    syn <- synth_categorical(x, n = 20, merge_rare = FALSE)
    expect_true(all(unique(x) %in% syn))
  }
})

test_that("factor sampling includes every observed level and preserves levels", {
  x <- factor(c(rep("common", 100), "rare", "uncommon"))
  set.seed(1)
  syn <- synth_categorical(x, n = 20, merge_rare = FALSE)

  expect_true(all(levels(x) %in% syn))
  expect_true(all(levels(x) %in% levels(syn)))
})

test_that("categorical sampling warns when the pool exceeds output size", {
  x <- c("a", "b", "c")

  expect_warning(
    syn <- synth_categorical(x, n = 2, merge_rare = FALSE),
    "Cannot guarantee categorical level presence"
  )
  expect_length(syn, 2)
})

test_that("categorical sampling is deterministic under a fixed seed", {
  x <- c(rep("common", 100), "rare", "uncommon")
  set.seed(42)
  first <- synth_categorical(x, n = 20, merge_rare = FALSE)
  set.seed(42)
  second <- synth_categorical(x, n = 20, merge_rare = FALSE)

  expect_identical(first, second)
})

test_that("rare_level_min_n sets the threshold", {
  set.seed(1)
  x <- c(rep("a", 30), rep("b", 6))
  # b (n = 6) survives a threshold of 5 but not one of 10.
  expect_true("b" %in% synth_categorical(x, n = 300, rare_level_min_n = 5))
  expect_false("b" %in% synth_categorical(x, n = 300, rare_level_min_n = 10))
})

test_that("free text routes through the same rare-level control", {
  set.seed(1)
  notes <- c(rep("no concerns", 40),
             "left-handed pilot from Sudbury with Fabry disease")
  syn <- synth_free_text(notes, n = 500, strategy = "categorical")

  expect_false("left-handed pilot from Sudbury with Fabry disease" %in% syn)
})

test_that("mask_rare replaces each rare categorical label without merging levels", {
  x <- c(rep("common", 12), rep("less common", 8),
         rep("beta rare", 3), rep("alpha rare", 2))

  set.seed(42)
  syn <- synth_categorical(
    x, n = 100, rare_level_min_n = 5,
    label_strategy = "mask_rare"
  )

  expect_false(any(c("alpha rare", "beta rare") %in% syn))
  placeholders <- grep("^Other category [0-9]+$", syn, value = TRUE)
  expect_setequal(unique(placeholders), c("Other category 1", "Other category 2"))
  expect_equal(length(unique(syn)), length(unique(x)))
  expect_true(all(c("common", "less common") %in% syn))

  set.seed(42)
  repeated <- synth_categorical(
    x, n = 100, rare_level_min_n = 5,
    label_strategy = "mask_rare"
  )
  expect_identical(syn, repeated)
})

test_that("mask_rare overrides rare merging and preserves factor levels", {
  x <- factor(c(rep("common", 12), "alpha rare", "beta rare"))
  set.seed(1)
  syn <- synth_categorical(
    x, n = 40, rare_level_min_n = 5,
    merge_rare = TRUE, label_strategy = "mask_rare"
  )

  expect_s3_class(syn, "factor")
  expect_false(any(c("alpha rare", "beta rare") %in% levels(syn)))
  expect_setequal(
    grep("^Other category [0-9]+$", levels(syn), value = TRUE),
    c("Other category 1", "Other category 2")
  )
  expect_false(".other" %in% syn)
  expect_equal(length(levels(syn)), length(levels(x)))
})

test_that("free text categorical synthesis honours mask_rare", {
  notes <- c(rep("no concerns", 10), "rare note one", "rare note two")
  set.seed(1)
  syn <- synth_free_text(
    notes, n = 30, strategy = "categorical",
    rare_level_min_n = 5, label_strategy = "mask_rare"
  )

  expect_false(any(c("rare note one", "rare note two") %in% syn))
  expect_setequal(
    grep("^Other category [0-9]+$", syn, value = TRUE),
    c("Other category 1", "Other category 2")
  )
})

test_that("unknown label_strategy aborts", {
  expect_error(
    synth_categorical(c("common", "rare"), n = 10, label_strategy = "unknown"),
    "Unknown label strategy"
  )
})

test_that("an all-NA column yields all NA", {
  expect_true(all(is.na(synth_categorical(c(NA, NA), n = 5))))
})
