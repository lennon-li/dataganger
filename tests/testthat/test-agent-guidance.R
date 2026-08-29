test_that("shipped Agent guidance keeps Agents away from real-data synthesis", {
  agent_skill_path <- testthat::test_path(
    "..",
    "..",
    "inst",
    "agent-skill",
    "SKILL.md"
  )
  if (!file.exists(agent_skill_path)) {
    agent_skill_path <- system.file(
      "agent-skill",
      "SKILL.md",
      package = "dataganger"
    )
  }
  agent_skill <- paste(
    readLines(agent_skill_path, warn = FALSE),
    collapse = "\n"
  )
  bundle_skill_path <- testthat::test_path(
    "..",
    "..",
    "inst",
    "skills",
    "using-dataganger-bundles",
    "SKILL.md"
  )
  if (!file.exists(bundle_skill_path)) {
    bundle_skill_path <- system.file(
      "skills",
      "using-dataganger-bundles",
      "SKILL.md",
      package = "dataganger"
    )
  }
  bundle_skill <- paste(
    readLines(bundle_skill_path, warn = FALSE),
    collapse = "\n"
  )
  workflow_vignette_path <- testthat::test_path(
    "..",
    "..",
    "vignettes",
    "privacy-and-ai-workflow.Rmd"
  )
  expect_match(agent_skill, "not a fitted generator", fixed = TRUE)
  expect_match(agent_skill, "trusted human or operator", fixed = TRUE)
  expect_match(agent_skill, "The real data and its path stay with", fixed = TRUE)
  expect_no_match(agent_skill, "<real-data>", fixed = TRUE)
  expect_no_match(agent_skill, "opaque input", fixed = TRUE)
  expect_no_match(agent_skill, "update `recipe.yaml`", fixed = TRUE)

  expect_match(bundle_skill, "not a fitted generator", fixed = TRUE)
  expect_match(bundle_skill, "trusted\\s+human or operator")
  expect_no_match(bundle_skill, "dataganger synthesize <real-data", fixed = TRUE)

  if (file.exists(workflow_vignette_path)) {
    workflow_vignette <- paste(
      readLines(workflow_vignette_path, warn = FALSE),
      collapse = "\n"
    )
    expect_match(workflow_vignette, "configuration, not a fitted generator", fixed = TRUE)
    expect_match(workflow_vignette, "trusted human or operator", fixed = TRUE)
    expect_no_match(workflow_vignette, "dataganger synthesize <real-data>", fixed = TRUE)
  }
})

test_that("generated human guidance reserves reruns for trusted operators", {
  tmp <- withr::local_tempdir()
  synthetic <- tibble::tibble(x = 1:3)
  attr(synthetic, "spec") <- synth_spec(purpose = "demo", seed = 1)
  class(synthetic) <- c("dataganger_synthetic", class(synthetic))

  out_dir <- file.path(tmp, "bundle")
  export_synthetic(synthetic, path = out_dir, format = "dir", include_report = FALSE)
  human_md <- paste(
    readLines(file.path(out_dir, "human", "human.md"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(human_md, "## Trusted operator rerun", fixed = TRUE)
  expect_match(human_md, "not a fitted generator", fixed = TRUE)
  expect_match(human_md, "must not rerun synthesis or modify the recipe", fixed = TRUE)
  expect_match(human_md, "trusted human or operator", fixed = TRUE)
  expect_match(human_md, "return that code to the trusted owner or operator", fixed = TRUE)
  expect_match(human_md, "inside the trusted environment", fixed = TRUE)
  expect_no_match(human_md, "then run the same pipeline on the real data", fixed = TRUE)
})
