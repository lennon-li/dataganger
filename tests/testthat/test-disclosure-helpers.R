test_that("dg_disclosure_option_meta returns the four privacy-first options in order", {
  m <- dg_disclosure_option_meta()
  expect_equal(vapply(m, `[[`, "", "value"), c("direct", "quasi", "sensitive", "none"))
  expect_match(m[[1]]$label, "Identifies a person directly")
  expect_match(m[[1]]$examples, "email")
  expect_match(m[[2]]$label, "Helps identify in combination")
  expect_match(m[[3]]$label, "private or sensitive")
  expect_match(m[[4]]$label, "measurement or value")
})

test_that("dg_derived_action maps classification to action", {
  expect_equal(dg_derived_action("direct"), "drop")
  expect_equal(dg_derived_action("quasi"), "synthesize")
  expect_equal(dg_derived_action("sensitive"), "synthesize")
  expect_equal(dg_derived_action("none"), "synthesize")
  expect_equal(dg_derived_action(NA_character_), "synthesize")
  expect_equal(dg_derived_action(""), "synthesize")
})

test_that("dg_treatment_text gives plain consequences, incl. auto-union", {
  expect_match(dg_treatment_text("direct"), "Removed")
  expect_match(dg_treatment_text("quasi"), "k-anonymity")
  expect_match(
    dg_treatment_text("sensitive", also_identifying = FALSE),
    "protected from linkage"
  )
  expect_match(
    dg_treatment_text("sensitive", also_identifying = TRUE),
    "k-anonymity"
  )
  expect_match(dg_treatment_text("none"), "distribution kept")
  expect_match(dg_treatment_text(NA_character_), "needs an answer")
})

test_that("dg_kanon_columns unions quasi with identifying-sensitive", {
  roles <- data.frame(
    variable = c("zip", "religion", "income", "name"),
    disclosure_role = c("quasi", "sensitive", "sensitive", "direct"),
    class = c("categorical candidate", "categorical candidate", "numeric", "free text"),
    stringsAsFactors = FALSE
  )
  out <- dg_kanon_columns(roles)
  expect_true(all(c("zip", "religion") %in% out))
  expect_false("income" %in% out)
  expect_false("name" %in% out)
})

test_that("dg_kanon_columns is empty/NA-safe", {
  expect_equal(dg_kanon_columns(NULL), character(0))
  roles <- data.frame(
    variable = "x",
    disclosure_role = NA_character_,
    class = "numeric",
    stringsAsFactors = FALSE
  )
  expect_equal(dg_kanon_columns(roles), character(0))
})

test_that("dg_suggest_disclosure maps detected class to a protective suggestion or unset", {
  expect_equal(dg_suggest_disclosure("ID candidate"), "direct")
  expect_equal(dg_suggest_disclosure("free text"), "direct")
  expect_equal(dg_suggest_disclosure("date"), "quasi")
  expect_equal(dg_suggest_disclosure("numeric"), "none")
  expect_equal(dg_suggest_disclosure("logical"), "none")
  expect_true(is.na(dg_suggest_disclosure("categorical candidate")))
  expect_true(is.na(dg_suggest_disclosure("unknown")))
})

test_that("dg_seed_disclosure seeds protective suggestions, leaves ambiguous unset", {
  roles <- data.frame(
    variable = c("id", "dob", "bp", "arm"),
    class = c("ID candidate", "date", "numeric", "categorical candidate"),
    disclosure_role = rep("", 4),
    stringsAsFactors = FALSE
  )
  out <- dg_seed_disclosure(roles)
  expect_equal(out$disclosure_role, c("direct", "quasi", "none", ""))
})
