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
})
