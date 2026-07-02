# Capture DataGangeR workflow screenshots + assemble the README hero GIF.
#
# Drives the installed Shiny app headlessly through all six workflow steps on a
# built-in sample dataset, screenshotting each step into man/figures/ (so both
# the README and the pkgdown site resolve them), then stitches the frames into
# man/figures/hero.gif.
#
# Re-run after any UI change to keep the docs current:
#   R CMD INSTALL --no-docs .   # so system.file() sees the new UI
#   Rscript data-raw/capture-screenshots.R
#
# Requires (author-time only, not package deps): shinytest2, magick, gifski.
# No proxy bypass is needed on this machine; the env vars below are harmless and
# keep it working on the proxied Asgard WSL too.

Sys.setenv(
  no_proxy = "127.0.0.1,localhost", NO_PROXY = "127.0.0.1,localhost",
  NOT_CRAN = "true"  # shinytest2 refuses to launch under a CRAN context
)

library(shinytest2)

W <- 1280L; H <- 800L
fig <- function(...) file.path("man", "figures", ...)
app_dir <- system.file("app", package = "dataganger")
stopifnot(nzchar(app_dir))

app <- AppDriver$new(
  app_dir, name = "dataganger-walkthrough",
  width = W, height = H, load_timeout = 90000, timeout = 30000
)
on.exit(try(app$stop(), silent = TRUE), add = TRUE)

shot <- function(file, pause = 0.6) {
  Sys.sleep(pause)
  unlink(fig(file))  # get_screenshot() refuses to overwrite
  # selector = "viewport" clips to the WxH window set above; the default
  # ("scrollable_area") captures the full scrollable page height instead,
  # which made step-3-configure.png a 4182px-tall strip next to compare's
  # 1264px square -- squished when placed side by side in the README table
  # and squashed again when gifski force-scales every frame to WxH.
  app$get_screenshot(fig(file), selector = "viewport")
  message("captured ", file, " (", file.info(fig(file))$size, " bytes)")
}

visible <- function(id)
  isTRUE(app$get_js(sprintf(
    "(function(e){return e && e.offsetParent !== null;})(document.getElementById('%s'))", id)))

# Both guardrail modals (module id "guardrail") re-show themselves from a
# reactive `observe()` until explicitly resolved, and can appear at more than
# one point in the flow -- so dismiss defensively wherever they might be
# showing rather than once at start.
dismiss_guardrail <- function() {
  if (visible("guardrail-agree")) {
    app$click("guardrail-agree", wait_ = FALSE); Sys.sleep(0.5)
  }
  # "Confirm and keep" clears the fail-safe's auto-assigned identifies value
  # for flagged columns back to blank (not drop them); the identifies loop
  # below sets "id" explicitly anyway, so this only unblocks the UI.
  if (visible("guardrail-confirm_keep_flagged")) {
    app$click("guardrail-confirm_keep_flagged", wait_ = FALSE); Sys.sleep(0.5)
  }
}
dismiss_guardrail()  # initial no-direct-identifiers attestation

# --- Step 01 · Upload ------------------------------------------------------
# Upload is step 1 and Objective is step 2 in the current wizard order (they
# swapped since this script was last updated for the v0.4.0 Configure UI).
shot("step-1-upload.png")  # empty dropzone + sample loader (the stable view)

app$click("upload-load_sample", wait_ = FALSE)
rows_ready <- function()
  isTRUE(suppressWarnings(as.numeric(app$get_js(
    "document.querySelectorAll('#data_panel-dp_table tbody tr').length"))) > 3)
for (i in 1:30) { if (rows_ready()) break; Sys.sleep(1) }
dismiss_guardrail()  # fail-safe fires once raw_data + roles are both set

# --- Step 02 · Objective ----------------------------------------------------
app$click("upload-go_roles", wait_ = FALSE)  # nav_request <- "objective"
for (i in 1:30) { Sys.sleep(1); if (visible("synthesis_controls-purpose_group")) break }
# wait_ = FALSE: this radio input doesn't invalidate a Shiny output, so the
# default wait blocks the full 30s timeout before falling through (matches
# every other set_inputs/click below, which already pass wait_ = FALSE).
app$set_inputs(`synthesis_controls-purpose_group` = "development", wait_ = FALSE)
shot("step-2-objective.png")

# --- Step 03 · Configure -------------------------------------------------
app$click("synthesis_controls-confirm_objective", wait_ = FALSE)  # -> Configure
for (i in 1:30) { Sys.sleep(1); if (visible("roles-k_anon")) break }
# Wait for the data preview table AND the (plain-HTML, renderUI-based) roles
# table to both finish rendering their rows -- the page frame and the roles
# panel's spinner appear before either table's rows exist, so firing the
# identifies/sensitive set_inputs loops too early is a silent no-op that
# leaves the two-question gate unsatisfied and Generate blocked forever.
roles_rows_ready <- function()
  isTRUE(suppressWarnings(as.numeric(app$get_js(
    "document.querySelectorAll('#roles-roles_table tbody tr').length"))) > 3)
for (i in 1:30) { if (rows_ready() && roles_rows_ready()) break; Sys.sleep(1) }

# Clear the two-question gate: every column needs a "Points to a person?"
# answer (identifies). "direct" is not a valid answer here: once the upload
# attestation confirms no direct identifiers, q1_identifies_choices() (see
# R/mod-roles.R) drops "direct" from Q1 entirely -- selecting it would
# contradict what was just attested. A realistic mix shows the derived
# actions well: id/age/sex -> combination (Coarsened), the rest -> none,
# with income & smoker also marked sensitive.
identifies <- c(id = "combination", age = "combination", sex = "combination",
                income = "none", education = "none", smoker = "none",
                bmi = "none")
for (i in seq_along(identifies)) {
  app$set_inputs(
    `roles-identifies_change` = list(row = i, value = unname(identifies[i])),
    allow_no_input_binding_ = TRUE, priority_ = "event", wait_ = FALSE
  )
  Sys.sleep(1)
}
# 0.6.0 Configure has no silent defaults: Generate is gated until every
# column has an explicit Sensitive? answer too, not just the "yes" ones.
sensitive <- c(id = "no", age = "no", sex = "no", income = "yes",
               education = "no", smoker = "yes", bmi = "no")
for (i in seq_along(sensitive)) {
  app$set_inputs(
    `roles-sensitive_change` = list(row = i, value = unname(sensitive[i])),
    allow_no_input_binding_ = TRUE, priority_ = "event", wait_ = FALSE
  )
  Sys.sleep(1)
}
# Capture Configure with the two-question panel up top and the per-column
# answers + Action override column populated.
shot("step-3-configure.png", pause = 3)

# --- Step 04 · Generate --------------------------------------------------
app$click("synthesis_controls-confirm"); Sys.sleep(2)
# The header CTA cycles generate -> cancel -> go_compare; click Generate, then
# poll until synthesis finishes and the "Continue to Compare" button binds.
app$click("generate-generate", wait_ = FALSE)
ok <- FALSE
for (i in 1:60) {
  Sys.sleep(1)
  done <- isTRUE(app$get_js(
    "document.getElementById('generate-go_compare') !== null"))
  if (done) { ok <- TRUE; break }
}
if (!ok) stop("synthesis did not complete within 60s")
shot("step-4-generate.png", pause = 1)

# --- Step 05 · Compare (real vs. synthetic distributions) ----------------
app$click("generate-go_compare", wait_ = FALSE); Sys.sleep(3)
shot("step-5-compare.png", pause = 1)

# --- Step 06 · Export ----------------------------------------------------
app$click("compare-go_export"); Sys.sleep(2)
shot("step-6-export.png")

app$stop()

# --- Assemble the hero GIF ----------------------------------------------
frames <- fig(sprintf("step-%d-%s.png", 1:6,
  c("upload","objective","configure","generate","compare","export")))
stopifnot(all(file.exists(frames)))
gifski::gifski(
  frames, gif_file = fig("hero.gif"),
  width = W, height = H, delay = 1.6, loop = TRUE, progress = FALSE
)
message("hero.gif: ", round(file.info(fig("hero.gif"))$size / 1024), " KB")

# Mirror all six step frames next to the pkgdown article, which can only resolve
# images that live in man/figures (bare) or in the vignette's own directory.
art <- file.path("vignettes", "articles")
if (dir.exists(art)) {
  file.copy(frames, art, overwrite = TRUE)
  message("copied ", length(frames), " step frames to ", art)
}

# Keep man/figures lean for the CRAN tarball: only the README references the
# hero GIF plus the Configure and Compare frames. The other four frames live
# only beside the article (build-ignored), so drop them from man/figures.
readme_keep <- fig(c("step-3-configure.png", "step-5-compare.png"))
unlink(setdiff(frames, readme_keep))
message("man/figures now holds: ", paste(list.files(fig()), collapse = ", "))
