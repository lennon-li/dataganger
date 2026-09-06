test_that("exact_row_match_flags flags the matching original and synthetic rows", {
  # Fixed-width string keys so the test exercises match logic, not numeric
  # formatting (row_key coerces via apply()/as.matrix, which pads numbers).
  original <- data.frame(
    a = sprintf("%02d", 1:30), b = rep(c("x", "y"), 15), stringsAsFactors = FALSE
  )
  synthetic <- data.frame(
    a = sprintf("%02d", 31:60), b = rep(c("y", "x"), 15), stringsAsFactors = FALSE
  )
  synthetic[c(3, 7), ] <- original[c(3, 7), ]  # inject two exact copies

  fl <- dataganger:::exact_row_match_flags(original, synthetic)

  expect_length(fl$original, nrow(original))
  expect_length(fl$synthetic, nrow(synthetic))
  expect_true(
    all(fl$synthetic[c(3, 7)]),
    info = paste("Synthetic flags:", paste(fl$synthetic, collapse = ", "))
  )
  expect_equal(sum(fl$synthetic), 2L)
  expect_true(
    all(fl$original[c(3, 7)]),
    info = paste("Original flags:", paste(fl$original, collapse = ", "))
  )
  expect_equal(sum(fl$original), 2L)
  # The synthetic-row flag count must equal the stat-box count exactly.
  expect_equal(sum(fl$synthetic), dataganger:::exact_row_match_count(original, synthetic))
})

test_that("exact_row_match_flags returns all-FALSE below 20 rows or with no synthetic", {
  small <- data.frame(a = 1:10)
  fl <- dataganger:::exact_row_match_flags(small, small)
  expect_false(any(fl$original), info = paste("Original flags:", paste(fl$original, collapse = ", ")))
  expect_false(any(fl$synthetic), info = paste("Synthetic flags:", paste(fl$synthetic, collapse = ", ")))

  fl2 <- dataganger:::exact_row_match_flags(
    data.frame(a = 1:30), data.frame(a = integer(0))
  )
  expect_false(any(fl2$original), info = paste("Original flags:", paste(fl2$original, collapse = ", ")))
  expect_length(fl2$synthetic, 0L)
})

test_that("exact_row_match_flags excludes alphanumeric-ID columns from matching", {
  original <- data.frame(
    id = sprintf("P%04d", 1:30), v = rep(1:2, 15), stringsAsFactors = FALSE
  )
  synthetic <- original
  synthetic$id <- sprintf("Q%04d", 1:30)  # IDs differ, but v is identical
  role_map <- c(id = "alphanumeric ID", v = "numeric")

  fl <- dataganger:::exact_row_match_flags(original, synthetic, role_map)
  # Every row matches on v once the ID column is excluded -- and this equals
  # the count, keeping highlight and stat box consistent.
  expect_true(all(fl$synthetic), info = paste("Synthetic flags:", paste(fl$synthetic, collapse = ", ")))
  expect_equal(sum(fl$synthetic), dataganger:::exact_row_match_count(original, synthetic, role_map))
})

test_that("exact-row keys preserve types, missingness, and delimiters", {
  original <- data.frame(
    whole = c(1L, rep(2L, 19)),
    text = c("a|b", rep("other", 19)),
    missing = c(NA_character_, rep("x", 19)),
    stringsAsFactors = FALSE
  )
  synthetic <- data.frame(
    whole = c(1, 2.5),
    text = c("a|b", "other"),
    missing = c(NA_character_, "<NA>"),
    stringsAsFactors = FALSE
  )

  expect_equal(dataganger:::exact_row_match_count(original, synthetic), 1L)
  na_original <- data.frame(x = rep(NA_character_, 20))
  na_synthetic <- data.frame(x = "<NA>")
  expect_equal(dataganger:::exact_row_match_count(na_original, na_synthetic), 0L)

  delimiter_original <- data.frame(
    a = c("a\001\002\003b", rep("other", 19)),
    b = c("c", rep("other", 19)), stringsAsFactors = FALSE
  )
  delimiter_synthetic <- data.frame(
    a = "a", b = "b\001\002\003c", stringsAsFactors = FALSE
  )
  expect_equal(dataganger:::exact_row_match_count(
    delimiter_original, delimiter_synthetic
  ), 0L)
})

test_that("exact-match summaries share session keys and reset with source release", {
  skip_if_not_installed("shiny")
  original <- data.frame(
    a = sprintf("%02d", 1:30), dx = rep(c("flu", "cold"), 15),
    stringsAsFactors = FALSE
  )
  synthetic <- original
  roles <- data.frame(
    variable = c("a", "dx"), sensitive = c(FALSE, TRUE),
    stringsAsFactors = FALSE
  )
  state <- shiny::reactiveValues(
    raw_data = original, synthetic = synthetic, exact_match_cache = NULL
  )
  shiny::isolate({
    first <- dataganger:::exact_match_state_summary(state, roles)
    second <- dataganger:::exact_match_state_summary(state, roles)
    expect_equal(first$n_matches, 30L)
    expect_identical(first, second)
    expect_length(state$exact_match_cache$bases, 1L)
    expect_length(state$exact_match_cache$summaries, 1L)
    expect_false("breakdown" %in% names(state$exact_match_cache$summaries[[1L]]$summary))

    # Changing only sensitivity reuses the row keys but recomputes severity.
    roles$sensitive <- c(FALSE, FALSE)
    amber <- dataganger:::exact_match_state_summary(state, roles)
    expect_equal(amber$n_sensitive, 0L)
    expect_length(state$exact_match_cache$bases, 1L)
    expect_length(state$exact_match_cache$summaries, 2L)

    # A match-column role change has a separate key set, and a new source drops
    # every old key/summary rather than retaining the prior private data.
    roles$recommended_role <- c("alphanumeric ID", "categorical")
    dataganger:::exact_match_state_summary(state, roles)
    expect_length(state$exact_match_cache$bases, 2L)
    state$synthetic <- synthetic[30:1, ]
    dataganger:::exact_match_state_summary(state, roles)
    expect_length(state$exact_match_cache$bases, 1L)

    cache <- state$exact_match_cache
    dataganger:::generator_workspace_release_source(state)
    expect_null(state$exact_match_cache)
    expect_null(cache$original)
    expect_null(cache$synthetic)
  })
})

test_that("exact-match detail is bounded and retains pair-to-row mapping", {
  columns <- sprintf("c%02d", 1:30)
  original <- as.data.frame(setNames(lapply(seq_along(columns), function(i) {
    sprintf("v%02d-%02d", i, seq_len(30))
  }), columns), stringsAsFactors = FALSE)
  # Row 2 is the same source record as row 1. Row 3 is a distinct match with
  # its sensitive value suppressed, so it remains amber rather than red.
  original[2, ] <- original[1, ]
  original$c30[[3L]] <- NA_character_
  synthetic <- original[c(1L, 3L), ]
  roles <- data.frame(
    variable = names(original),
    sensitive = names(original) == "c30",
    stringsAsFactors = FALSE
  )
  summary <- dataganger:::exact_match_summary(original, synthetic, roles)
  expect_equal(summary$n_matches, 2L)
  expect_equal(summary$n_sensitive, 1L)
  expect_equal(summary$n_pairs, 60L)
  expect_equal(summary$original_rows, c(1L, 3L))
  expect_equal(summary$original_severity[1:2], c(2L, 2L))
  expect_equal(summary$original_severity[[3L]], 1L)
  expect_equal(summary$synthetic_severity, c(2L, 1L))

  page <- dataganger:::exact_match_detail(
    original, synthetic, roles, summary = summary, offset = 24L, limit = 24L
  )
  expect_equal(nrow(page$breakdown), 24L)
  expect_equal(page$breakdown$column[[1L]], "c25")
  expect_equal(page$breakdown$synthetic_row[[1L]], 1L)
  expect_equal(page$breakdown$column[[7L]], "c01")
  expect_equal(page$breakdown$synthetic_row[[7L]], 2L)
  expect_equal(page$breakdown$original_row[[7L]], 3L)

  last <- dataganger:::exact_match_detail(
    original, synthetic, roles, summary = summary, offset = 48L, limit = 24L
  )
  expect_equal(nrow(last$breakdown), 12L)
  expect_equal(last$breakdown$column[[12L]], "c30")
  expect_equal(last$breakdown$synthetic_row[[12L]], 2L)
})
