test_that("detect_roles() returns correct S3 class and columns", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  r <- detect_roles(df)
  expect_s3_class(r, "dataganger_roles")
  expect_named(r, c("variable", "class", "recommended_role", "user_role", "reason", "sensitive"))
  expect_equal(r$variable, c("x", "y"))
})

test_that("detect_roles() detects ID candidate from high cardinality", {
  set.seed(123)
  df <- data.frame(id = 1:50)
  r <- detect_roles(df)
  expect_equal(r$recommended_role[r$variable == "id"], "ID candidate")
  expect_match(r$reason[r$variable == "id"], "n_distinct/nrow")
})

test_that("detect_roles() does NOT flag high-cardinality as ID when nrow < 20", {
  # Column named "col_x" to avoid triggering ID name pattern
  df <- data.frame(col_x = 1:10)
  r <- detect_roles(df)
  expect_false(r$recommended_role[r$variable == "col_x"] == "ID candidate")
})

test_that("detect_roles() detects ID from column name pattern", {
  # Use data that does NOT trigger the cardinality-based ID check
  # n_distinct=3, nrow=25 → ratio 0.12 < 0.95, so only name triggers ID
  df <- data.frame(patient_id = rep(1:3, length.out = 25))
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "ID candidate")
  expect_match(r$reason[1], "name matches ID pattern")
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
  expect_match(r$reason[1], "haven_labelled")
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

test_that("detect_roles() detects geography from column name", {
  # Use data with moderate cardinality to avoid earlier thresholds
  # 50 rows, 30 distinct values → 30/50=0.6, >=0.05, not ID (<0.95),
  # n_distinct=30 > 20, so doesn't hit categorical
  geo_names <- c("zip", "postal", "fsa", "county", "region", "province",
                 "state", "city", "geo", "lat", "lon", "coord")
  for (nm in geo_names) {
    n <- 50
    vals <- sample(seq_len(30), n, replace = TRUE)
    df <- setNames(data.frame(x = vals), nm)
    r <- detect_roles(df)
    expect_equal(r$recommended_role[1], "geography", info = nm)
  }
})

test_that("detect_roles() returns unknown for columns with no match", {
  # 50 rows, exactly 30 distinct values → n_distinct=30
  # ratio 30/50=0.6, >=0.05 and <0.95 AND n_distinct=30 > 20
  # So doesn't hit ID (ratio < 0.95), doesn't hit categorical (ratio >= 0.05 AND > 20)
  # Name "normal_col" matches no patterns → unknown
  df <- data.frame(
    normal_col = c(1:30, 1:20),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_equal(r$recommended_role[1], "unknown")
})

test_that("detect_roles() marks ID, date, geography, free text as sensitive", {
  df <- data.frame(
    record_id  = rep(1:3, length.out = 50),
    visit_date = as.Date("2024-01-01") + 1:50,
    city_name  = sample(30:59, 50, replace = TRUE),
    stringsAsFactors = FALSE
  )
  r <- detect_roles(df)
  expect_true(r$sensitive[r$variable == "record_id"])
  expect_true(r$sensitive[r$variable == "visit_date"])
  # city_name with moderate cardinality → geography → sensitive
  expect_true(r$sensitive[r$variable == "city_name"])
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

test_that("detect_roles() rejects non-data-frame", {
  expect_error(detect_roles("not a df"), "must be a data frame")
})
