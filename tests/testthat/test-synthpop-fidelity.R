# Behavioral tests for the synthpop engine: assert the *contract* (relationships
# preserved, no silent drops, graceful fallback), not just the wiring.

test_that("synthpop preserves a correlation that the internal engine destroys", {
  skip_if_not_installed("synthpop")
  set.seed(1)
  n <- 400
  x <- rnorm(n)
  df <- data.frame(
    x = x,
    y = 2 * x + rnorm(n, sd = 0.3),         # strong linear relationship
    grp = factor(ifelse(x > 0, "hi", "lo"))  # related to x
  )
  roles <- detect_roles(df)
  orig_cor <- abs(stats::cor(df$x, df$y))

  spec_int <- synth_spec("demo", seed = 1L)                          # none -> internal
  syn_int <- synthesize_data(df, spec_int, roles = roles)
  cor_int <- abs(stats::cor(syn_int$x, syn_int$y))

  spec_sp <- suppressWarnings(synth_spec("development", seed = 1L))  # moderate -> synthpop
  syn_sp <- synthesize_data(df, spec_sp, roles = roles)
  expect_equal(attr(syn_sp, "engine"), "synthpop")
  cor_sp <- abs(stats::cor(syn_sp$x, syn_sp$y))

  expect_lt(cor_int, 0.3)                # marginal engine breaks the relationship
  expect_gt(cor_sp, 0.85 * orig_cor)     # synthpop keeps most of it
  expect_gt(cor_sp, cor_int)             # and is materially better than marginal
})

test_that("distinctive numeric survives synthpop; only the ID-named column drops", {
  skip_if_not_installed("synthpop")
  set.seed(2)
  df <- data.frame(
    patient_label = paste0("P", 1:200),    # name + cardinality -> ID candidate -> dropped
    lab_value = round(rnorm(200, 50, 8), 2), # distinctive numeric -> numeric role -> kept
    arm = rep(c("A", "B"), 100),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  expect_equal(roles$recommended_role[roles$variable == "lab_value"], "numeric")
  expect_equal(roles$recommended_role[roles$variable == "patient_label"], "ID candidate")

  spec <- suppressWarnings(synth_spec("development", seed = 2L))
  syn <- synthesize_data(df, spec, roles = roles)
  expect_equal(attr(syn, "engine"), "synthpop")
  expect_true("lab_value" %in% names(syn))
  expect_false("patient_label" %in% names(syn))
  expect_gt(length(unique(syn$lab_value)), 1L)  # non-degenerate
})

test_that("density smoothing keeps continuous values within a sane envelope", {
  skip_if_not_installed("synthpop")
  set.seed(3)
  df <- data.frame(pct = runif(300, 0, 100), age = round(rnorm(300, 40, 10)))
  roles <- detect_roles(df)
  spec <- suppressWarnings(synth_spec("development", seed = 3L))
  syn <- synthesize_data(df, spec, roles = roles)
  expect_equal(attr(syn, "engine"), "synthpop")

  # Density smoothing can leak mildly past observed bounds (a few % over the max
  # is expected for a Gaussian kernel); guard only against gross out-of-range.
  rng <- diff(range(df$pct))
  expect_gt(min(syn$pct), min(df$pct) - 0.1 * rng)
  expect_lt(max(syn$pct), max(df$pct) + 0.1 * rng)
})

test_that("derived synthpop falls back to internal with a warning when synthpop is unavailable", {
  local_mocked_bindings(synthpop_available = function() FALSE)
  df <- data.frame(x = rnorm(30), y = rnorm(30))
  roles <- detect_roles(df)
  spec <- suppressWarnings(synth_spec("development", seed = 1L))  # derived -> synthpop
  expect_warning(
    syn <- synthesize_data(df, spec, roles = roles),
    "marginal engine"
  )
  expect_equal(attr(syn, "engine"), "internal")
})

test_that("explicit engine = 'synthpop' errors when synthpop is unavailable", {
  local_mocked_bindings(synthpop_available = function() FALSE)
  df <- data.frame(x = rnorm(30), y = rnorm(30))
  roles <- detect_roles(df)
  spec <- synth_spec("demo")
  expect_error(
    synthesize_data(df, spec, roles = roles, engine = "synthpop"),
    "synthpop"
  )
})
