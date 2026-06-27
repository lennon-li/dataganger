
test_that("detect_roles() returns correct S3 class and columns", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  r <- detect_roles(df)
  expect_s3_class(r, "dataganger_roles")
  expect_named(
    r,
    c(
      "variable", "class", "recommended_role", "user_role", "simulation",
      "reason", "disclosure_role", "disclosure_reason"
    )
  )
  expect_equal(r$variable, c("x", "y"))
  expect_equal(r$simulation, c("synthesize", "synthesize"))
})

test_that("detect_roles assigns disclosure_role per the conservative policy", {
  set.seed(123)
  df <- data.frame(
    patient_id = sprintf("P%04d", 1:50),
    zip = rep(c("M5V", "M4C"), 25),
    visit_date = as.Date("2020-01-01") + 0:49,
    sex = rep(c("F", "M"), 25),
    lab_value = rnorm(50),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  expect_true("disclosure_role" %in% names(roles))
  expect_true("disclosure_reason" %in% names(roles))
  dr <- stats::setNames(roles$disclosure_role, roles$variable)
  expect_equal(dr[["patient_id"]], "direct")
  expect_true(is.na(dr[["zip"]]))
  expect_true(is.na(dr[["visit_date"]]))
  expect_true(is.na(dr[["sex"]]))
  expect_true(is.na(dr[["lab_value"]]))
})

test_that("detect_roles() detects ID candidate from high cardinality", {
  set.seed(123)
  df <- data.frame(token = sprintf("tok-%03d", 1:50))
  r <- detect_roles(df)
  expect_equal(r$recommended_role[r$variable == "token"], "ID candidate")
  expect_match(r$reason[r$variable == "token"], "Nearly every value is unique")
})

test_that("detect_roles() does NOT flag high-cardinality as ID when nrow < 20", {
  # Column named "col_x" to avoid triggering ID name pattern
  df <- data.frame(col_x = 1:10)
  r <- detect_roles(df)
  expect_false(r$recommended_role[r$variable == "col_x"] == "ID candidate")
})

test_that("detect_roles() labels distinctive numeric as numeric, not ID candidate", {
  # High-cardinality numeric with no ID-like name: users classify it in the UI,
  # so it must NOT be auto-flagged as an identifier (design intent).
  df <- data.frame(measurement = seq(1.1, 50.1, length.out = 50))
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "numeric")
  expect_false(r$recommended_role[1] == "ID candidate")
})

test_that("detect_roles() still flags distinctive numeric as ID when name matches", {
  df <- data.frame(record_id = seq(1.1, 50.1, length.out = 50))
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "ID candidate")
  expect_match(r$reason[1], "suggests an identifier")
})

test_that("detect_roles() still flags distinctive character as ID candidate", {
  df <- data.frame(token = sprintf("tok-%03d", 1:50))
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "ID candidate")
})

test_that("detect_roles() detects ID from column name pattern", {
  # Use data that does NOT trigger the cardinality-based ID check
  # n_distinct=3, nrow=25 → ratio 0.12 < 0.95, so only name triggers ID
  df <- data.frame(patient_id = rep(1:3, length.out = 25))
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "ID candidate")
  expect_match(r$reason[1], "suggests an identifier")
})

test_that("detect_roles() detects multiple ID name patterns", {
  patterns <- c("id", "record_id", "subject", "patient", "record", "case_no")
  for (nm in patterns) {
    df <- setNames(data.frame(x = rep(1:3, length.out = 25)), nm)
    r <- detect_roles(df)
    expect_equal(r$recommended_role[1], "ID candidate", info = nm)
  }
})

test_that("detect_roles() detects date columns", {
  df <- data.frame(
    d1 = as.Date("2024-01-01") + 1:5,
    d2 = as.POSIXct("2024-01-01 12:00:00") + 1:5
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[r$variable == "d1"], "date")
  expect_equal(r$recommended_role[r$variable == "d2"], "date")
})

test_that("detect_roles() detects haven_labelled columns", {
  df <- data.frame(
    status = haven::labelled(
      c(1, 2, 1, 2, 1),
      labels = c(Active = 1, Inactive = 2)
    ),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "label_check")
  expect_match(r$reason[1], "labelled survey codes")
})

test_that("detect_roles() detects categorical candidate (low cardinality ratio)", {
  df <- data.frame(
    small = rep(letters[1:3], length.out = 50),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[r$variable == "small"], "categorical candidate")
})

test_that("detect_roles() detects categorical candidate (n_distinct <= 20)", {
  df <- data.frame(
    x = factor(rep(letters[1:15], each = 10)),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "categorical candidate")
})

test_that("detect_roles() detects free text", {
  # 60 unique long strings, each > 50 characters
  # 100 rows → n_distinct=60 > nrow*0.5=50, mean_nchar > 50
  # ratio 0.6 < 0.95, n_distinct=60 > 20 → not ID, not categorical
  base_strings <- sprintf(
    "very_long_unique_text_for_testing_free_text_number_%030d",
    1:60
  )
  notes <- c(base_strings, sample(base_strings, 40, replace = TRUE))
  df <- data.frame(notes = notes, stringsAsFactors = FALSE)
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "free text")
})

test_that("detect_roles() classifies long narrative text as free text before ID", {
  df <- data.frame(
    note_id = sprintf(
      "patient follow up note describing symptoms, medications, and context %03d",
      1:30
    ),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "free text")
})

test_that("detect_roles() classifies geographic names by cardinality, not a special role", {
  low_card <- data.frame(
    region = rep(c("north", "south", "east", "west", "central"), each = 6),
    stringsAsFactors = FALSE
  )
  low_roles <- detect_roles(low_card)
  expect_equal(low_roles$recommended_role[1], "categorical candidate")

  high_card <- data.frame(
    region = sprintf("region-%03d", 1:50),
    stringsAsFactors = FALSE
  )
  high_roles <- detect_roles(high_card)
  expect_equal(high_roles$recommended_role[1], "ID candidate")
})

test_that("detect_roles() labels a distinctive numeric column as numeric", {
  # 50 rows, exactly 30 distinct values → n_distinct=30
  # ratio 30/50=0.6, >=0.05 and <0.95 AND n_distinct=30 > 20
  # Not ID (ratio < 0.95), not categorical (ratio >= 0.05 AND > 20), numeric class
  # Name "normal_col" matches no patterns → numeric (user classifies via UI)
  df <- data.frame(
    normal_col = c(1:30, 1:20),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "numeric")
})

test_that("detect_roles maps confident identifiers to direct, leaves rest unselected", {
  df <- data.frame(
    record_id  = rep(1:3, length.out = 50),
    visit_date = as.Date("2024-01-01") + 1:50,
    city_name  = sample(30:59, 50, replace = TRUE),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$disclosure_role[r$variable == "record_id"], "direct")
  expect_true(is.na(r$disclosure_role[r$variable == "visit_date"]))
  expect_true(is.na(r$disclosure_role[r$variable == "city_name"]))
})

test_that("detect_roles() user_role is initially NA", {
  df <- data.frame(x = 1:5)
  r <- detect_roles(df)
  expect_true(is.na(r$user_role[1]))
})

test_that("detect_roles() accepts a profile argument and reuses it", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  p <- profile_data(df)
  r <- detect_roles(df, profile = p)
  expect_s3_class(r, "dataganger_roles")
  expect_equal(nrow(r), 2)
})

test_that("print.dataganger_roles works without error", {
  df <- data.frame(x = rep(1:3, length.out = 25))
  r <- detect_roles(df)
  expect_s3_class(r, "dataganger_roles")
  expect_no_error(print(r))
})

test_that("detect_roles() does not classify long character values as ID even at high cardinality", {
  # 50 unique strings each ~30 chars, no spaces — high cardinality but long values
  vals <- sprintf("item-description-key-value-%03d", 1:50)
  df <- data.frame(item_desc = vals, stringsAsFactors = FALSE)
  r <- detect_roles(df)
  expect_false(r$recommended_role[1] == "ID candidate",
               label = "long char column should not be classified as ID candidate")
})

test_that("detect_roles() rejects non-data-frame", {
  expect_error(detect_roles("not a df"), "must be a data frame")
})

# Regression: Bug 5 — character-stored dates were classified "unknown" and fed
# to synthpop as high-cardinality factors, hanging CART.
test_that("detect_roles() classifies ISO date strings as 'date'", {
  df <- data.frame(
    event_date = format(as.Date("2020-01-01") + 1:50, "%Y-%m-%d"),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[r$variable == "event_date"], "date")
})

test_that("detect_roles() classifies 'Month DD, YYYY' date strings as 'date'", {
  df <- data.frame(
    report_date = format(as.Date("2019-06-01") + 1:50, "%b %e, %Y"),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[r$variable == "report_date"], "date")
})

test_that("detect_roles() does not classify non-date strings as 'date'", {
  df <- data.frame(
    code = sprintf("CASE-%04d", 1:50),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_false(r$recommended_role[1] == "date",
               label = "arbitrary code strings should not be classified as date")
})

test_that("detect_roles leaves uncertain columns unselected (NA disclosure_role)", {
  set.seed(1)
  df <- data.frame(
    patient_id = sprintf("P%04d", 1:50),
    zip        = rep(c("M5V", "M4C"), 25),
    visit_date = as.Date("2020-01-01") + 0:49,
    sex        = rep(c("F", "M"), 25),
    case_count = sample(1:9, 50, TRUE),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  dr <- stats::setNames(r$disclosure_role, r$variable)
  expect_equal(dr[["patient_id"]], "direct")
  expect_true(is.na(dr[["zip"]]))
  expect_true(is.na(dr[["visit_date"]]))
  expect_true(is.na(dr[["sex"]]))
  expect_true(is.na(dr[["case_count"]]))
})

test_that("detect_roles auto-assigns sensitive for known-sensitive names", {
  df <- data.frame(
    diagnosis = rep(c("flu", "cold"), 25),
    race      = rep(c("a", "b"), 25),
    income    = rnorm(50),
    treatment = rep(c("x", "y"), 25),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  dr <- stats::setNames(r$disclosure_role, r$variable)
  expect_equal(dr[["diagnosis"]], "sensitive")
  expect_equal(dr[["race"]], "sensitive")
  expect_equal(dr[["income"]], "sensitive")
  expect_true(is.na(dr[["treatment"]]))
})

test_that("detect_roles sensitive-name heuristic rejects near-miss false positives", {
  df <- data.frame(
    trace_element      = rnorm(50),
    sewage_volume      = rnorm(50),
    unconditional_prob = rnorm(50),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  dr <- stats::setNames(r$disclosure_role, r$variable)
  expect_true(is.na(dr[["trace_element"]]))
  expect_true(is.na(dr[["sewage_volume"]]))
  expect_true(is.na(dr[["unconditional_prob"]]))
})

test_that("detect_roles leaves geographic categorical columns unselected for disclosure", {
  df <- data.frame(city = rep(c("Toronto", "Montreal"), 25), stringsAsFactors = FALSE)
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "categorical candidate")
  expect_true(is.na(r$disclosure_role[1]))
})
