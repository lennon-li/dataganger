local({
  fit_roles <- function(data, role = NULL, simulation = NULL,
                        postal_country = NULL, postal_format = NULL) {
    n <- ncol(data)
    result <- tibble::tibble(
      variable = names(data),
      recommended_role = rep("numeric", n),
      user_role = rep(NA_character_, n),
      simulation = rep("synthesize", n),
      label_strategy = rep(NA_character_, n),
      postal_strategy = rep(NA_character_, n),
      postal_country = rep(NA_character_, n)
    )
    result$recommended_role[vapply(data, is.character, logical(1))] <- "categorical candidate"
    result$recommended_role[vapply(data, is.logical, logical(1))] <- "logical"
    result$recommended_role[vapply(data, inherits, logical(1), what = "Date")] <- "date"
    result$recommended_role[vapply(data, inherits, logical(1), what = "POSIXct")] <- "date"
    if (!is.null(role)) result$recommended_role[match(names(role), result$variable)] <- unname(role)
    if (!is.null(simulation)) result$simulation[match(names(simulation), result$variable)] <- unname(simulation)
    if (!is.null(postal_country)) result$postal_country[match(names(postal_country), result$variable)] <- unname(postal_country)
    if (!is.null(postal_format)) result$postal_format <- unname(postal_format[names(data)])
    class(result) <- c("dataganger_roles", class(result))
    result
  }

  fit_spec <- function(...) {
    synth_spec("demo", engine = "internal", ...)
  }

  test_that("the internal compiler retains aggregate summaries only", {
    data <- data.frame(
      amount = c(1.2, 2.4, NA, 4.8, 5.1, 6.3),
      count = c(1L, 2L, 2L, 4L, NA, 5L),
      group = factor(c("north", "north", "south", "south", NA, "north")),
      flag = c(TRUE, FALSE, TRUE, NA, FALSE, TRUE),
      day = as.Date("2020-01-01") + c(0, 1, 2, NA, 4, 5),
      stamp = as.POSIXct("2020-01-01 12:00:00", tz = "America/Toronto") + c(0, 60, 120, NA, 240, 300),
      when = c("01/01/2020", "01/02/2020", "01/03/2020", NA, "01/05/2020", "01/06/2020"),
      clock = c("12:00", "12:01", "12:02", NA, "12:04", "12:05"),
      stringsAsFactors = FALSE
    )
    roles <- fit_roles(data, role = c(when = "date", clock = "date"))
    fitted <- fit_internal_generator(data, fit_spec(rare_level_min_n = 2, label_strategy = "preserve"), roles)
    repeated <- fit_internal_generator(data, fit_spec(rare_level_min_n = 2, label_strategy = "preserve"), roles)

    expect_s3_class(fitted, "dataganger_generator")
    expect_true(fitted$eligible)
    # The private exact-row key is CSPRNG-generated at each freeze, so the
    # secret-bearing index is intentionally different across independent fits.
    expect_identical(fitted$columns, repeated$columns)
    expect_identical(fitted$risk_report, repeated$risk_report)
    expect_s3_class(fitted$risk_report, "dataganger_generator_risk_report")
    expect_identical(names(fitted$columns), names(data))
    expect_identical(fitted$columns$amount$kind, "numeric")
    expect_identical(fitted$columns$count$storage, "integer")
    expect_identical(fitted$columns$group$kind, "categorical")
    expect_identical(fitted$columns$group$levels, c("north", "south"))
    expect_identical(fitted$columns$flag$kind, "logical")
    expect_identical(fitted$columns$day$kind, "date")
    expect_identical(fitted$columns$stamp$timezone, "America/Toronto")
    expect_identical(fitted$columns$when$kind, "character_date")
    expect_true(fitted$columns$clock$has_time)
    fitted_factor_flags <- vapply(fitted$columns, is.factor, logical(1))
    expect_false(
      any(fitted_factor_flags),
      info = paste("Factor-valued fitted columns:", paste(names(fitted_factor_flags)[fitted_factor_flags], collapse = ", "))
    )
    expect_true(generator_fitted_state_audit(fitted, list(amount = data$amount))$clean)
  })

  test_that("all-missing and degenerate supported columns are explicit", {
    data <- data.frame(
      all_missing = as.numeric(c(NA, NA, NA)),
      constant = c(7L, 7L, 7L),
      stringsAsFactors = FALSE
    )
    fitted <- fit_internal_generator(data, fit_spec(), fit_roles(data))

    expect_true(fitted$eligible)
    expect_identical(fitted$columns$all_missing$kind, "all_missing")
    expect_identical(fitted$columns$constant$distribution, "degenerate")
    expect_identical(fitted$columns$constant$value, 7)
  })

  test_that("short numeric summaries fail closed before an aggregate can replay source values", {
    source <- data.frame(value = c(0, 5, 10))
    fitted <- fit_internal_generator(source, fit_spec(), fit_roles(source))

    expect_false(fitted$eligible)
    expect_true("insufficient_numeric_support" %in% fitted$risk_report$blockers$code)
    expect_true("aggregate_source_collision" %in% fitted$risk_report$blockers$code)
    expect_length(fitted$columns, 0L)
  })

  test_that("aggregate collision checks ignore source ordering", {
    source <- data.frame(value = c(10, 0, 5))
    fitted <- fit_internal_generator(source, fit_spec(), fit_roles(source))

    expect_false(fitted$eligible)
    expect_true("aggregate_source_collision" %in% fitted$risk_report$blockers$code)
  })

  test_that("date range summaries fail closed when they reproduce a short source", {
    data <- data.frame(
      day = as.Date(c("2020-01-02", "2020-01-01")),
      stamp = as.POSIXct(c("2020-01-02 12:00:00", "2020-01-01 12:00:00"), tz = "UTC"),
      when = c("2020-01-02", "2020-01-01"),
      stringsAsFactors = FALSE
    )
    roles <- fit_roles(data, role = c(when = "date"))
    fitted <- fit_internal_generator(data, fit_spec(), roles)

    expect_false(fitted$eligible)
    expect_identical(
      fitted$risk_report$blockers$code,
      rep("aggregate_source_collision", 3L)
    )
    expect_identical(
      fitted$risk_report$blockers$column,
      c("day", "stamp", "when")
    )
  })

  test_that("malformed specifications fail closed without compiling columns", {
    data <- data.frame(value = c(1, 2, 2, 4, 5))
    roles <- fit_roles(data)

    for (bad in list(1, list(), list(engine = "internal"))) {
      fitted <- fit_internal_generator(data, bad, roles)
      expect_false(fitted$eligible)
      expect_true("invalid_spec" %in% fitted$risk_report$blockers$code)
      expect_length(fitted$columns, 0L)
    }

    bad_label <- fit_spec()
    bad_label$label_strategy <- c("preserve", "mask_rare")
    bad_text <- fit_spec()
    bad_text$free_text_strategy <- c("drop", "redact")
    text_roles <- fit_roles(data, role = c(value = "free_text"))

    label_fit <- fit_internal_generator(data, bad_label, roles)
    text_fit <- fit_internal_generator(data, bad_text, text_roles)
    expect_false(label_fit$eligible)
    expect_true("invalid_label_strategy" %in% label_fit$risk_report$blockers$code)
    expect_false(text_fit$eligible)
    expect_true("invalid_free_text_strategy" %in% text_fit$risk_report$blockers$code)

    fractional_rare <- fit_spec(rare_level_min_n = 2.5)
    invalid_dates <- fit_spec(coarsen_dates = c(TRUE, FALSE))
    invalid_merge <- fit_spec(merge_rare = "yes")
    fractional_fit <- fit_internal_generator(data, fractional_rare, roles)
    date_fit <- fit_internal_generator(data, invalid_dates, roles)
    merge_fit <- fit_internal_generator(data, invalid_merge, roles)
    expect_true("invalid_rare_threshold" %in% fractional_fit$risk_report$blockers$code)
    expect_true("invalid_date_coarsening" %in% date_fit$risk_report$blockers$code)
    expect_true("invalid_rare_merge" %in% merge_fit$risk_report$blockers$code)

    huge_rare <- fit_spec(rare_level_min_n = .Machine$integer.max + 1)
    huge_fit <- fit_internal_generator(data, huge_rare, roles)
    expect_false(huge_fit$eligible)
    expect_true("invalid_rare_threshold" %in% huge_fit$risk_report$blockers$code)
  })

  test_that("roles require approved compiler fields, order, actions, and roles", {
    data <- data.frame(first = 1:5, second = 6:10)
    roles <- fit_roles(data)
    missing_action <- roles[, setdiff(names(roles), "simulation")]
    duplicate <- rbind(roles, roles[1, ])
    reordered <- roles[2:1, ]
    unknown_action <- roles
    unknown_action$simulation[1] <- "invent"
    unknown_role <- roles
    unknown_role$recommended_role[1] <- "invent"

    for (bad in list(missing_action, duplicate, reordered, unknown_action, unknown_role)) {
      fitted <- fit_internal_generator(data, fit_spec(), bad)
      expect_false(fitted$eligible)
      expect_true("roles_invalid" %in% fitted$risk_report$blockers$code)
      expect_length(fitted$columns, 0L)
    }
  })

  test_that("engine omission derives only the internal compiler path", {
    data <- data.frame(value = c(1, 2, 2, 4, 5))
    roles <- fit_roles(data)
    auto <- fit_internal_generator(data, synth_spec("demo"), roles)
    derived_synthpop <- fit_internal_generator(data, synth_spec("development"), roles)
    legacy <- fit_internal_generator(data, synth_spec("demo", engine = "marginal"), roles)

    expect_true(auto$eligible)
    expect_false(derived_synthpop$eligible)
    expect_true("engine_ineligible" %in% derived_synthpop$risk_report$blockers$code)
    expect_true(legacy$eligible)
  })

  test_that("the input class whitelist rejects custom and container columns", {
    custom <- data.frame(value = 1:5)
    custom$value <- structure(as.numeric(custom$value), class = "custom_numeric")
    labelled <- data.frame(value = haven::labelled(1:5, c(one = 1L)))
    contained <- data.frame(value = I(list(1:2, 3:4, 5:6, 7:8, 9:10)))

    for (data in list(custom, labelled, contained)) {
      fitted <- fit_internal_generator(data, fit_spec(), fit_roles(data))
      expect_false(fitted$eligible)
      expect_identical(fitted$risk_report$blockers$code, "unsupported_class")
    }
  })

  test_that("risk reports fail closed with stable column codes", {
    data <- data.frame(
      pass = c("a", "a", "b", "b", "a"),
      scramble = c("x", "x", "y", "y", "x"),
      notes = c("long private note one", "long private note two", "long private note three", "long private note four", "long private note five"),
      category = c("rare", "common", "common", "common", "common"),
      stringsAsFactors = FALSE
    )
    roles <- fit_roles(
      data,
      role = c(notes = "free text"),
      simulation = c(pass = "pass_through", scramble = "scramble")
    )
    fitted <- fit_internal_generator(
      data,
      fit_spec(label_strategy = "preserve", preserve_missingness = "exact"),
      roles
    )

    expect_false(fitted$eligible)
    expect_s3_class(fitted$risk_report, "dataganger_generator_risk_report")
    expect_identical(
      fitted$risk_report$blockers$code,
      c("exact_missingness", "pass_through", "scramble", "free_text_unsafe", "unsafe_rare_labels")
    )
    expect_identical(
      fitted$risk_report$blockers$column,
      c(NA_character_, "pass", "scramble", "notes", "category")
    )
  })

  test_that("free-text aliases and direct identifiers cannot retain observed labels", {
    data <- data.frame(value = rep(c("private-a", "private-b"), each = 5))
    free_text <- fit_roles(data, role = c(value = "free_text"))
    direct_id <- fit_roles(data, role = c(value = "alphanumeric ID"))

    free_fit <- fit_internal_generator(data, fit_spec(), free_text)
    id_fit <- fit_internal_generator(data, fit_spec(), direct_id)

    expect_false(free_fit$eligible)
    expect_true("free_text_unsafe" %in% free_fit$risk_report$blockers$code)
    expect_false(id_fit$eligible)
    expect_true("direct_identifier" %in% id_fit$risk_report$blockers$code)
    expect_length(free_fit$columns, 0L)
    expect_length(id_fit$columns, 0L)
  })

  test_that("masking, merge, and approved drop remove unsafe categorical content", {
    data <- data.frame(
      masked = c("secret-a", "common", "common", "common", "common"),
      merged = c("secret-b", "common", "common", "common", "common"),
      notes = c("private one", "private two", "private three", "private four", "private five"),
      stringsAsFactors = FALSE
    )
    roles <- fit_roles(data, role = c(notes = "free text"))
    roles$label_strategy[roles$variable == "merged"] <- "preserve"
    fitted <- fit_internal_generator(
      data,
      fit_spec(merge_rare = TRUE, free_text_strategy = "redact"),
      roles
    )

    expect_true(fitted$eligible)
    expect_match(fitted$columns$masked$levels[[1]], "^Other category")
    expect_true(".other" %in% fitted$columns$merged$levels)
    expect_identical(fitted$columns$notes$kind, "redacted")
    retained_values <- unlist(fitted$columns, use.names = FALSE)
    retained_private_flags <- grepl("secret|private", retained_values)
    expect_false(
      any(retained_private_flags),
      info = paste("Private fitted values:", paste(retained_values[retained_private_flags], collapse = ", "))
    )
  })

  test_that("engine, constraints, postal metadata, and classes are blocked", {
    data <- data.frame(value = c(1, 2, 2, 4, 5), zip = c("M5V 1E3", "M5V 1E3", "M5V 1E3", "M5V 1E3", "M5V 1E3"))
    roles <- fit_roles(data, role = c(zip = "postal code"))
    bad_engine <- fit_internal_generator(data, synth_spec("demo", engine = "synthpop"), roles)
    expect_false(bad_engine$eligible)
    expect_true("engine_ineligible" %in% bad_engine$risk_report$blockers$code)

    constrained <- fit_internal_generator(data, fit_spec(constraints = list(value = "x > 0")), roles)
    expect_true("unsafe_constraints" %in% constrained$risk_report$blockers$code)
    expect_true("postal_parameters_missing" %in% constrained$risk_report$blockers$code)

    approved_roles <- roles
    approved_roles$postal_country[approved_roles$variable == "zip"] <- "CA"
    approved_roles$postal_format <- c(NA_character_, "ca-postal-v1")
    approved_postal <- fit_internal_generator(data, fit_spec(), approved_roles)
    expect_true(approved_postal$eligible)
    expect_identical(approved_postal$columns$zip, list(
      kind = "postal", country = "CA", format = "ca-postal-v1", missing_rate = 0
    ))

    unsupported <- data.frame(value = I(list(1:2, 3:4, 5:6, 7:8, 9:10)))
    unsupported_fit <- fit_internal_generator(unsupported, fit_spec(), fit_roles(unsupported))
    expect_true("unsupported_class" %in% unsupported_fit$risk_report$blockers$code)

    empty_postal <- data.frame(zip = rep(NA_character_, 3L), stringsAsFactors = FALSE)
    empty_postal_roles <- fit_roles(empty_postal, role = c(zip = "postal code"))
    empty_postal_fit <- fit_internal_generator(empty_postal, fit_spec(), empty_postal_roles)
    expect_false(empty_postal_fit$eligible)
    expect_true("postal_parameters_missing" %in% empty_postal_fit$risk_report$blockers$code)
  })

  test_that("recursive and serialized canary audits find injected retention", {
    source <- data.frame(value = c(11, 22, 33, 44, 55), group = c("a", "a", "b", "b", "a"))
    fitted <- fit_internal_generator(source, fit_spec(), fit_roles(source))
    source_vector <- source$value
    rm(source)
    gc()
    restored <- unserialize(serialize(fitted, NULL))

    expect_invisible(validate_internal_generator(restored))
    clean <- generator_fitted_state_audit(restored, list(source_vector = source_vector, text = "FG2-CANARY-TEXT"))
    expect_true(clean$clean)
    expect_length(clean$findings$source_vectors, 0L)
    expect_length(clean$findings$serialized_canaries, 0L)

    restored$injected_vector <- source_vector
    restored$injected_text <- "FG2-CANARY-TEXT"
    restored$injected_row <- data.frame(marker = "FG2-CANARY-ROW")
    found <- generator_fitted_state_audit(restored, list(source_vector = source_vector, text = "FG2-CANARY-TEXT"))
    expect_false(found$clean)
    expect_true("source_vector" %in% found$findings$source_vectors)
    expect_true(length(found$findings$source_data_frames) > 0L)
    expect_true("text" %in% found$findings$serialized_canaries)
    # A clean audit is evidence only; it cannot prove the absence of all leakage.
  })

  test_that("fitted-state audits reject attributes and unsafe structures", {
    state <- list(value = 1:3)
    attr(state, "injected_numeric") <- c(11, 22, 33)
    attributed <- generator_fitted_state_audit(state, list(numeric = c(11, 22, 33)))
    expect_false(attributed$clean)
    expect_true(length(attributed$findings$unsafe_attributes) > 0L)
    expect_true("numeric" %in% attributed$findings$source_vectors)

    unsafe <- list(
      pair = pairlist(a = 1L),
      call = quote(identity(1)),
      fn = function() NULL,
      env = new.env(parent = emptyenv())
    )
    unsafe_audit <- generator_fitted_state_audit(unsafe)
    expect_false(unsafe_audit$clean)
    expect_length(unsafe_audit$findings$unsafe_state, 4L)

    if (!methods::isClass("dg_fit_audit_s4")) {
      methods::setClass("dg_fit_audit_s4", slots = c(payload = "numeric"))
    }
    s4_audit <- generator_fitted_state_audit(
      list(s4 = methods::new("dg_fit_audit_s4", payload = c(7, 8))),
      list(slot_vector = c(7, 8))
    )
    expect_false(s4_audit$clean)
    expect_true("slot_vector" %in% s4_audit$findings$source_vectors)

    raw_canary <- as.raw(1:4)
    raw_audit <- generator_fitted_state_audit(list(raw = raw_canary), list(raw = raw_canary))
    expect_false(raw_audit$clean)
    expect_true("raw" %in% raw_audit$findings$source_vectors)

    encoded <- "FG2-ENCODED-\u00e9"
    clean <- generator_fitted_state_audit(list(note = "ordinary"), list(encoded = encoded))
    expect_true(clean$clean)
    encoded_audit <- generator_fitted_state_audit(list(note = encoded), list(encoded = encoded))
    expect_true("encoded" %in% encoded_audit$findings$serialized_canaries)

    hidden_names <- list(value = stats::setNames(1:3, c("secret-a", "secret-b", "secret-c")))
    names_audit <- generator_fitted_state_audit(
      hidden_names,
      list(hidden_names = c("secret-a", "secret-b", "secret-c"))
    )
    expect_false(names_audit$clean)
    expect_true("hidden_names" %in% names_audit$findings$source_vectors)
  })

  test_that("generator validation rejects report and eligibility tampering", {
    data <- data.frame(value = c(1, 2, 2, 4, 5))
    fitted <- fit_internal_generator(data, fit_spec(), fit_roles(data))
    contradictory <- fitted
    contradictory$eligible <- FALSE
    expect_error(validate_internal_generator(contradictory), class = "dataganger_generator_schema_error")

    malformed <- fitted
    malformed$risk_report$blockers <- list(code = "bad")
    expect_error(validate_internal_generator(malformed), class = "dataganger_generator_schema_error")

    blocked <- fit_internal_generator(data, synth_spec("development"), fit_roles(data))
    blocked$columns <- list(retained = list(kind = "numeric"))
    expect_error(validate_internal_generator(blocked), class = "dataganger_generator_schema_error")

    unnamed <- fitted
    names(unnamed$columns) <- NULL
    expect_error(validate_internal_generator(unnamed), class = "dataganger_generator_schema_error")

    hidden_class <- fitted
    class(hidden_class) <- c("dataganger_generator", "secret-a", "secret-b")
    expect_error(validate_internal_generator(hidden_class), class = "dataganger_generator_schema_error")
  })
})
