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
  app$get_screenshot(fig(file))
  message("captured ", file, " (", file.info(fig(file))$size, " bytes)")
}

# --- Step 01 · Objective -------------------------------------------------
app$set_inputs(`synthesis_controls-purpose_group` = "development")
shot("step-1-objective.png")

# --- Step 02 · Upload ----------------------------------------------------
app$click("synthesis_controls-confirm_objective", wait_ = FALSE); Sys.sleep(1.5)
shot("step-2-upload.png")  # empty dropzone + sample loader (the stable view)

# --- Step 03 · Configure -------------------------------------------------
# Loading a sample auto-advances Upload -> Configure once profiling finishes.
app$click("upload-load_sample", wait_ = FALSE)
visible <- function(id)
  isTRUE(app$get_js(sprintf(
    "(function(e){return e && e.offsetParent !== null;})(document.getElementById('%s'))", id)))
for (i in 1:30) { Sys.sleep(1); if (visible("roles-k_anon")) break }
if (visible("upload-go_roles")) { app$click("upload-go_roles", wait_ = FALSE); Sys.sleep(1.5) }
# Wait for the DataTables (roles + data preview) to actually render their rows;
# the page frame appears before the tables finish, leaving a spinner otherwise.
rows_ready <- function()
  isTRUE(suppressWarnings(as.numeric(app$get_js(
    "document.querySelectorAll('#data_panel-dp_table tbody tr').length"))) > 3)
for (i in 1:30) { if (rows_ready()) break; Sys.sleep(1) }

# Clear the two-question gate: every column needs a "Points to a person?"
# answer (identifies). A realistic mix shows the derived actions well:
#   id -> direct (Removed), age/sex -> combination (Coarsened),
#   the rest -> none, with income & smoker also marked sensitive.
identifies <- c(id = "direct", age = "combination", sex = "combination",
                income = "none", education = "none", smoker = "none",
                bmi = "none")
for (i in seq_along(identifies)) {
  app$set_inputs(
    `roles-identifies_change` = list(row = i, value = unname(identifies[i])),
    allow_no_input_binding_ = TRUE, priority_ = "event", wait_ = FALSE
  )
  Sys.sleep(0.2)
}
for (i in c(4L, 6L)) {  # income, smoker -> Sensitive? = Yes
  app$set_inputs(
    `roles-sensitive_change` = list(row = i, value = "yes"),
    allow_no_input_binding_ = TRUE, priority_ = "event", wait_ = FALSE
  )
  Sys.sleep(0.2)
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
  c("objective","upload","configure","generate","compare","export")))
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
