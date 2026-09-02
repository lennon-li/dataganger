local({
  test_that("private exact-row fingerprints detect complete output rows", {
    source <- data.frame(value = rep(7L, 5L))
    roles <- tibble::tibble(
      variable = "value",
      recommended_role = "numeric",
      user_role = NA_character_,
      simulation = "synthesize",
      label_strategy = NA_character_,
      postal_strategy = NA_character_,
      postal_country = NA_character_,
      disclosure_role = "none",
      identifies = "none",
      sensitive = FALSE
    )
    class(roles) <- c("dataganger_roles", class(roles))
    generator <- fit_internal_generator(source, synth_spec("demo", engine = "internal"), roles)
    check <- generator_runtime_privacy_check(source, generator, roles)

    expect_true(check$ok == FALSE)
    expect_identical(check$exact_match_count, 5L)
    expect_identical(check$blockers$code, "exact_row_match")
  })

  test_that("privacy failure returns no usable generated artifact", {
    source <- data.frame(value = rep(7L, 5L))
    roles <- tibble::tibble(
      variable = "value",
      recommended_role = "numeric",
      user_role = NA_character_,
      simulation = "synthesize",
      label_strategy = NA_character_,
      postal_strategy = NA_character_,
      postal_country = NA_character_,
      disclosure_role = "none",
      identifies = "none",
      sensitive = FALSE
    )
    class(roles) <- c("dataganger_roles", class(roles))
    generator <- fit_internal_generator(source, synth_spec("demo", engine = "internal"), roles)
    result <- generate_internal_generator(generator, seed = 1, n = 5)

    expect_false(result$usable)
    expect_length(result$outputs, 0L)
    expect_identical(result$privacy[[1L]]$exact_match_count, 5L)
    expect_identical(result$blockers[[1L]]$code, "exact_row_match")
  })

  test_that("fail-closed exact-row privacy check behavior", {
    source <- data.frame(value = rep(7L, 5L))
    roles <- tibble::tibble(
      variable = "value",
      recommended_role = "numeric",
      user_role = NA_character_,
      simulation = "synthesize",
      label_strategy = NA_character_,
      postal_strategy = NA_character_,
      postal_country = NA_character_,
      disclosure_role = "none",
      identifies = "none",
      sensitive = FALSE
    )
    class(roles) <- c("dataganger_roles", class(roles))
    generator_base <- fit_internal_generator(source, synth_spec("demo", engine = "internal"), roles)

    # 1. exact_row_index is NULL
    gen <- generator_base
    gen$exact_row_index <- NULL
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_false(check$ok)
    expect_contains(check$blockers$code, "exact_row_check_unavailable")

    # 2. exact_row_index is not a list (e.g., character)
    gen <- generator_base
    gen$exact_row_index <- "invalid"
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_false(check$ok)
    expect_contains(check$blockers$code, "exact_row_check_unavailable")

    # 3. index present but key not raw
    gen <- generator_base
    gen$exact_row_index$key <- "not_raw"
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_false(check$ok)
    expect_contains(check$blockers$code, "exact_row_check_unavailable")

    # 4. index present but fingerprints not character
    gen <- generator_base
    gen$exact_row_index$fingerprints <- 123
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_false(check$ok)
    expect_contains(check$blockers$code, "exact_row_check_unavailable")

    # 5. index present but algorithm absent
    gen <- generator_base
    gen$exact_row_index$algorithm <- NULL
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_false(check$ok)
    expect_contains(check$blockers$code, "exact_row_check_unavailable")

    # 6. index present but algorithm set to an unrecognized value
    gen <- generator_base
    gen$exact_row_index$algorithm <- "HMAC-SHA256-canonical-v1"
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_false(check$ok)
    expect_contains(check$blockers$code, "exact_row_check_unavailable")

    # 7. well-formed index with fingerprints = character() PASSES
    gen <- generator_base
    gen$exact_row_index$fingerprints <- character()
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_true(check$ok)
    expect_false("exact_row_check_unavailable" %in% check$blockers$code)
    expect_false("exact_row_match" %in% check$blockers$code)

    # 8. well-formed index with fingerprints that do not match the synthetic rows PASSES
    gen <- generator_base
    gen$exact_row_index$fingerprints <- "non_matching_fingerprint"
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_true(check$ok)
    expect_false("exact_row_check_unavailable" %in% check$blockers$code)
    expect_false("exact_row_match" %in% check$blockers$code)

    # 9. well-formed index whose fingerprints DO match still yields the exact_row_match blocker
    gen <- generator_base
    check <- generator_runtime_privacy_check(source, gen, roles)
    expect_false(check$ok)
    expect_false("exact_row_check_unavailable" %in% check$blockers$code)
    expect_contains(check$blockers$code, "exact_row_match")
  })
})
