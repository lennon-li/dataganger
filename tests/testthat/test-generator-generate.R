local({
  runtime_fixture <- function() {
    data <- data.frame(
      amount = seq(1.1, 40.1, by = 1),
      count = as.integer(seq_len(40)),
      group = rep(c("north", "south"), 20),
      flag = rep(c(TRUE, FALSE), 20),
      day = as.Date("2020-01-01") + seq_len(40) * 3,
      when = format(as.Date("2020-01-01") + seq_len(40) * 3, "%Y-%m-%d"),
      stringsAsFactors = FALSE
    )
    roles <- detect_roles(data)
    roles$disclosure_role <- "none"
    roles$identifies <- "none"
    roles$sensitive <- FALSE
    roles$user_identifies <- NA_character_
    roles$user_sensitive <- NA
    roles$user_role <- NA_character_
    roles$simulation <- "synthesize"
    list(
      data = data,
      roles = roles,
      generator = fit_internal_generator(
        data,
        synth_spec("demo", engine = "internal", k_anon = 2),
        roles
      )
    )
  }

  test_that("fitted generation does not need the source data", {
    fixture <- runtime_fixture()
    generator <- fixture$generator
    source_vector <- fixture$data$amount
    rm(fixture)
    gc()

    result <- generate_internal_generator(generator, seed = 42, n = 80)
    expect_true(result$usable)
    expect_length(result$outputs, 1L)
    expect_equal(nrow(result$outputs[[1L]]), 80L)
    expect_true(generator_fitted_state_audit(
      generator,
      list(source_vector = source_vector)
    )$clean)
  })

  test_that("runtime batches are deterministic and isolate ambient RNG", {
    fixture <- runtime_fixture()
    before <- withr::with_seed(901, .Random.seed)
    first <- withr::with_seed(901, {
      initial <- .Random.seed
      value <- generate_internal_generator(fixture$generator, seed = 17, n = 80, datasets = 2)
      list(initial = initial, value = value, final = .Random.seed)
    })
    expect_identical(first$initial, first$final)
    expect_identical(before, withr::with_seed(901, .Random.seed))

    second <- generate_internal_generator(fixture$generator, seed = 17, n = 80, datasets = 2)
    expect_identical(first$value$seeds, second$seeds)
    expect_identical(first$value$outputs, second$outputs)
    changed <- generate_internal_generator(fixture$generator, seed = 18, n = 80)
    expect_false(identical(first$value$outputs[[1L]], changed$outputs[[1L]]))

    original_kind <- RNGkind()
    on.exit(do.call(RNGkind, as.list(original_kind)), add = TRUE)
    suppressWarnings(RNGkind("Super-Duper", "Kinderman-Ramage", "Rounding"))
    set.seed(321)
    ambient_kind <- RNGkind()
    ambient_seed <- .Random.seed
    alternate <- generate_internal_generator(
      fixture$generator, seed = 17, n = 80, datasets = 2
    )
    expect_identical(RNGkind(), ambient_kind)
    expect_identical(.Random.seed, ambient_seed)
    expect_identical(first$value$seeds, alternate$seeds)
    expect_identical(
      vapply(first$value$outputs, generator_data_hash, character(1L)),
      vapply(alternate$outputs, generator_data_hash, character(1L))
    )
  })

  test_that("runtime replays fitted supported types and enforcement metadata", {
    fixture <- runtime_fixture()
    result <- generate_internal_generator(fixture$generator, seed = 99, n = 80)
    expect_true(result$usable)
    output <- result$outputs[[1L]]
    expect_true(is.numeric(output$amount))
    expect_true(is.integer(output$count))
    expect_true(is.character(output$group))
    expect_true(is.logical(output$flag))
    expect_s3_class(output$day, "Date")
    expect_true(is.character(output$when))
    expect_true("kanon" %in% names(attributes(output)))
    expect_true(is.list(result$privacy[[1L]]$kanon))
    expect_true(is.list(result$diagnostics[[1L]]))
  })

  test_that("generic naming is applied after k-anonymity", {
    fixture <- runtime_fixture()
    spec <- synth_spec("demo", engine = "internal", name_strategy = "generic", k_anon = 2)
    generator <- fit_internal_generator(fixture$data, spec, fixture$roles)
    result <- generate_internal_generator(generator, seed = 11, n = 80)
    expect_true(result$usable)
    expect_identical(names(result$outputs[[1L]]), paste0("col_", seq_len(6L)))
    expect_true("kanon" %in% names(attributes(result$outputs[[1L]])))
  })

  test_that("runtime output postconditions fail closed", {
    fixture <- runtime_fixture()
    contract <- generator_contract(
      generator_derive_policy(fixture$generator),
      generation_limits(seed = c(1L, 100L), n = c(20L, 100L)),
      generator_derive_compatibility()
    )
    request <- generation_request(contract, list(seed = 2L, n = 40L, datasets = 1L))
    result <- generator_generate(fixture$generator, request = request, contract = contract)
    expect_true(result$usable)
    broken <- result$outputs[[1L]]
    names(broken)[[1L]] <- "wrong"
    issues <- generator_runtime_output_issues(broken, request, contract)
    expect_true("output_schema_mismatch" %in% vapply(issues, `[[`, character(1L), "code"))
  })
})
