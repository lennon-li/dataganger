local({
  make_generator_policy <- function() {
    list(
      privacy = list(k = 5L, rare_labels = "mask"),
      columns = list(
        list(
          name = "age",
          type = "numeric",
          role = "quasi",
          simulation = "resample"
        )
      ),
      naming = list(strategy = "preserve")
    )
  }

  make_generator_contract <- function() {
    generator_contract(
      policy = make_generator_policy(),
      allowed = generation_limits(
        seed = c(1L, 1000L),
        n = c(100L, 500L),
        datasets = c(1L, 4L)
      ),
      compatibility = list(engine = "internal", compiler = "1.0.0")
    )
  }

  test_that("canonical JSON recursively sorts object keys", {
    first <- list(
      z = list(beta = 2L, alpha = 1L),
      a = list(list(y = TRUE, x = "value"), 3L)
    )
    second <- list(
      a = list(list(x = "value", y = TRUE), 3),
      z = list(alpha = 1, beta = 2)
    )

    expect_identical(canonical_json(first), canonical_json(second))
    expect_identical(semantic_hash(first), semantic_hash(second))
    expect_match(semantic_hash(first), "^[0-9a-f]{64}$")
  })

  test_that("canonicalization preserves array order", {
    expect_false(
      identical(
        semantic_hash(list(values = list("a", "b"))),
        semantic_hash(list(values = list("b", "a")))
      )
    )
  })

  test_that("canonical data hashing handles a missing double safely", {
    expect_no_error(generator_data_hash_double(NA_real_))
  })

  test_that("canonicalization handles null and named atomic values", {
    first <- list(value = c(beta = 2L, alpha = 1L), optional = NULL)
    second <- list(optional = NULL, value = c(alpha = 1, beta = 2))

    expect_identical(canonical_json(first), canonical_json(second))
  })

  test_that("canonicalization rejects unsafe or ambiguous content", {
    unsafe <- list(
      function() NULL,
      quote(system("whoami")),
      new.env(parent = emptyenv()),
      structure("secret", class = "unsafe_payload"),
      structure(list(a = 1L), note = "x"),
      pairlist(a = 1L),
      data.frame(x = 1L),
      matrix(1:4, nrow = 2L),
      NA_character_,
      Inf,
      NaN,
      1 + 2i,
      as.raw(1L)
    )

    for (value in unsafe) {
      expect_error(
        canonical_json(list(value = value)),
        class = "dataganger_generator_unsafe_content_error"
      )
    }

    expect_error(
      canonical_json(stats::setNames(list(1L), "")),
      class = "dataganger_generator_unsafe_content_error"
    )
    expect_error(
      canonical_json(structure(list(1L, 2L), names = c("x", "x"))),
      class = "dataganger_generator_unsafe_content_error"
    )
    expect_error(
      canonical_json(structure(list(1L, 2L), names = c("x", ""))),
      class = "dataganger_generator_unsafe_content_error"
    )

    expect_no_error(canonical_json(list(a = 1L)))
    expect_no_error(canonical_json(list(1L)))
  })

  test_that("generation limits are bounded integer ranges", {
    limits <- generation_limits(
      seed = c(0L, 100L),
      n = c(10L, 1000L),
      datasets = c(1L, 8L)
    )

    expect_s3_class(limits, "dataganger_generation_limits")
    expect_identical(names(limits), c("seed", "n", "datasets"))
    expect_identical(limits$n, c(10L, 1000L))
    expect_invisible(validate_generation_limits(limits))

    bad_ranges <- list(
      list(n = c(0L, 10L)),
      list(n = c(10L, 9L)),
      list(n = c(1, 2.5)),
      list(datasets = c(0L, 2L)),
      list(seed = c(-1L, 2L)),
      list(seed = c(1L, NA_integer_))
    )

    for (args in bad_ranges) {
      expect_error(
        do.call(generation_limits, args),
        class = "dataganger_generator_validation_error"
      )
    }
  })

  test_that("contract IDs are stable across recursive list order", {
    first <- make_generator_contract()
    policy <- make_generator_policy()
    policy <- policy[c("naming", "columns", "privacy")]
    policy$privacy <- policy$privacy[c("rare_labels", "k")]
    second <- generator_contract(
      compatibility = list(compiler = "1.0.0", engine = "internal"),
      allowed = generation_limits(
        datasets = c(1L, 4L),
        n = c(100L, 500L),
        seed = c(1L, 1000L)
      ),
      policy = policy
    )

    expect_s3_class(first, "dataganger_contract")
    expect_identical(first$policy, second$policy)
    expect_identical(first$compatibility, second$compatibility)
    expect_identical(first$contract_id, second$contract_id)
    expect_invisible(validate_generator_contract(first))
  })

  test_that("privacy-sensitive contract mutations change the ID", {
    original <- make_generator_contract()

    mutations <- list(
      within(make_generator_policy(), privacy$k <- 10L),
      within(make_generator_policy(), columns[[1L]]$role <- "sensitive"),
      within(make_generator_policy(), columns[[1L]]$simulation <- "drop"),
      within(make_generator_policy(), naming$strategy <- "generic")
    )

    for (policy in mutations) {
      changed <- generator_contract(
        policy = policy,
        allowed = original$allowed,
        compatibility = original$compatibility
      )
      expect_false(identical(changed$contract_id, original$contract_id))
    }

    changed_limits <- generator_contract(
      policy = original$policy,
      allowed = generation_limits(
        seed = c(1L, 1000L),
        n = c(100L, 600L),
        datasets = c(1L, 4L)
      ),
      compatibility = original$compatibility
    )
    expect_false(identical(changed_limits$contract_id, original$contract_id))
  })

  test_that("contract validation detects tampering", {
    contract <- make_generator_contract()
    tampered <- contract
    tampered$policy$privacy$k <- 2L

    expect_error(
      validate_generator_contract(tampered),
      class = "dataganger_generator_tamper_error"
    )
  })

  test_that("contract validation fails closed on schema and top-level fields", {
    contract <- make_generator_contract()

    future <- contract
    future$schema_version <- 2L
    expect_error(
      validate_generator_contract(future),
      "schema version 2",
      class = "dataganger_generator_schema_error"
    )

    unknown <- contract
    unknown$future_policy <- TRUE
    expect_error(
      validate_generator_contract(unknown),
      "Unknown field",
      class = "dataganger_generator_schema_error"
    )

    missing <- contract[names(contract) != "policy"]
    expect_error(
      validate_generator_contract(missing),
      "Missing field",
      class = "dataganger_generator_schema_error"
    )

    malformed <- contract
    malformed$contract_version <- "latest"
    expect_error(
      validate_generator_contract(malformed),
      class = "dataganger_generator_schema_error"
    )

    malformed_schema <- contract
    malformed_schema$schema_version <- NA_integer_
    expect_error(
      validate_generator_contract(malformed_schema),
      "schema_version must be one integer",
      class = "dataganger_generator_schema_error"
    )

    malformed_id <- contract
    malformed_id$contract_id <- "not-a-hash"
    expect_error(
      validate_generator_contract(malformed_id),
      class = "dataganger_generator_schema_error"
    )

    wrong_class <- structure(unclass(contract), class = "foreign_contract")
    expect_error(
      validate_generator_contract(wrong_class),
      class = "dataganger_generator_schema_error"
    )

    expect_error(
      generator_contract(
        policy = list(),
        allowed = contract$allowed,
        compatibility = contract$compatibility
      ),
      class = "dataganger_generator_schema_error"
    )
  })

  test_that("generation requests accept only a bounded request overlay", {
    contract <- make_generator_contract()
    request <- generation_request(
      contract,
      list(seed = 42L, n = 250L, datasets = 3L)
    )

    expect_s3_class(request, "dataganger_generation_request")
    expect_identical(request$contract_id, contract$contract_id)
    expect_identical(request$seed, 42L)
    expect_identical(request$n, 250L)
    expect_identical(request$datasets, 3L)
    expect_match(request$request_id, "^[0-9a-f]{64}$")
    expect_invisible(validate_generation_request(request, contract))
  })

  test_that("generation requests reject bounds and fixed-field overrides", {
    contract <- make_generator_contract()
    invalid <- list(
      list(seed = 0L, n = 250L, datasets = 1L),
      list(seed = 42L, n = 99L, datasets = 1L),
      list(seed = 42L, n = 501L, datasets = 1L),
      list(seed = 42L, n = 250L, datasets = 5L),
      list(seed = c(1L, 2L), n = 250L, datasets = 3L),
      list(seed = 1.5, n = 250L, datasets = 1L),
      list(seed = 42L, n = c(200L, 250L), datasets = 1L),
      list(seed = 42L, n = 250L, datasets = c(1L, 2L)),
      list(seed = 42L, n = 250L, datasets = 1L, policy = list(k = 1L)),
      list(seed = 42L, n = 250L, datasets = 1L, contract_id = "other"),
      list(seed = 42L, n = 250L, datasets = 1L, future = TRUE)
    )

    for (overlay in invalid) {
      expect_error(
        generation_request(contract, overlay),
        class = "dataganger_generator_request_error"
      )
    }


    expect_error(
      generation_request(contract, list(42L, 250L, 1L)),
      class = "dataganger_generator_request_error"
    )
    duplicate <- structure(
      list(42L, 250L, 1L),
      names = c("seed", "n", "n")
    )
    expect_error(
      generation_request(contract, duplicate),
      class = "dataganger_generator_request_error"
    )
  })

  test_that("contract and request summaries expose metadata without policy values", {
    contract <- make_generator_contract()
    request <- generation_request(
      contract,
      list(seed = 42L, n = 250L, datasets = 3L)
    )

    contract_summary <- summary(contract)
    expect_s3_class(contract_summary, "summary_dataganger_contract")
    expect_identical(contract_summary$contract_id, contract$contract_id)
    expect_identical(contract_summary$policy_sections, c("columns", "naming", "privacy"))
    expect_null(contract_summary[["policy"]])
    expect_match(
      paste(capture.output(print(contract)), collapse = "\n"),
      contract$contract_id,
      fixed = TRUE
    )

    request_summary <- summary(request)
    expect_s3_class(request_summary, "summary_dataganger_generation_request")
    expect_identical(request_summary$request_id, request$request_id)
    expect_identical(request_summary$n, 250L)
    expect_match(
      paste(capture.output(print(request)), collapse = "\n"),
      request$request_id,
      fixed = TRUE
    )
  })

  test_that("request validation detects request and contract tampering", {
    contract <- make_generator_contract()
    request <- generation_request(
      contract,
      list(seed = 42L, n = 250L, datasets = 1L)
    )

    changed_request <- request
    changed_request$n <- 300L
    expect_error(
      validate_generation_request(changed_request, contract),
      class = "dataganger_generator_tamper_error"
    )

    changed_contract <- make_generator_contract()
    changed_contract <- generator_contract(
      policy = within(make_generator_policy(), privacy$k <- 10L),
      allowed = changed_contract$allowed,
      compatibility = changed_contract$compatibility
    )
    expect_error(
      validate_generation_request(request, changed_contract),
      class = "dataganger_generator_request_error"
    )

    wrong_class <- structure(unclass(request), class = "foreign_request")
    expect_error(
      validate_generation_request(wrong_class, contract),
      class = "dataganger_generator_request_error"
    )

    unknown <- unclass(request)
    unknown$future <- TRUE
    expect_error(
      validate_generation_request(unknown, contract),
      class = "dataganger_generator_request_error"
    )
  })

  test_that("generator errors share common programmatic classes", {
    error <- tryCatch(
      generation_request(
        make_generator_contract(),
        list(seed = 42L, n = 1L, datasets = 1L)
      ),
      error = identity
    )

    expect_s3_class(error, "dataganger_generator_request_error")
    expect_s3_class(error, "dataganger_generator_validation_error")
    expect_s3_class(error, "dataganger_generator_error")
  })

  test_that("canonical data hashes are portable and type-sensitive", {
    data <- data.frame(
      number = c(1e-300, 1e300, NA_real_, NaN),
      text = c("NA", NA_character_, "x", "x"),
      group = factor(c("a", "b", NA, "a"), levels = c("a", "b", "unused")),
      day = as.Date("2020-01-01") + c(0, 1, NA, 3),
      stringsAsFactors = FALSE
    )
    hash <- generator_data_hash(data)
    expect_identical(hash, generator_data_hash(tibble::as_tibble(data)))
    expect_identical(nchar(hash), 64L)

    changed <- data
    changed$text[[1L]] <- NA_character_
    expect_false(identical(hash, generator_data_hash(changed)))
    changed <- data
    levels(changed$group) <- c("a", "b", "different")
    expect_false(identical(hash, generator_data_hash(changed)))
    changed <- data[c(2L, 1L, 3L, 4L), ]
    expect_false(identical(hash, generator_data_hash(changed)))

    ordered <- data
    ordered$group <- ordered(ordered$group)
    expect_false(identical(hash, generator_data_hash(ordered)))

    instant <- as.POSIXct("2020-01-01 00:00:00", tz = "UTC")
    precise <- data.frame(at = instant + c(0, 0.0000001))
    rounded <- data.frame(at = instant + c(0, 0.0000002))
    expect_false(identical(
      generator_data_hash(precise),
      generator_data_hash(rounded)
    ))

    withr::local_options(list(OutDec = ",", scipen = 999))
    expect_identical(hash, generator_data_hash(data))
  })
})
