# Full-flow browser harness for DataGangeR Shiny app
# Tests: load sample → roles → spec → generate → compare → export
#
# Run from repo root:
#   NOT_CRAN=true Rscript tests/browser_harness.R

message("=== DataGangeR Browser Harness ===")

library(shinytest2)

# ── Install from source so the Shiny subprocess sees the latest R/ code ───────
# Run this script from the repo root: Rscript tests/browser_harness.R
repo_root <- normalizePath(".")
stopifnot("Must be run from repo root" = file.exists(file.path(repo_root, "DESCRIPTION")))
message("Installing package from source...")
install.packages(repo_root, repos = NULL, type = "source", quiet = TRUE,
                 INSTALL_opts = "--no-docs --no-multiarch")
message("  done")
app_dir <- file.path(repo_root, "inst", "app")

# ── Proxy bypass (Asgard WSL) ─────────────────────────────────────────────────
Sys.setenv(no_proxy = "127.0.0.1,localhost", NO_PROXY = "127.0.0.1,localhost")
chromote::set_chrome_args(c(
  "--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu",
  "--proxy-server=http://204.40.194.129:3128",
  "--proxy-bypass-list=127.0.0.1;localhost"
))

# ── Helpers ───────────────────────────────────────────────────────────────────

pass <- function(msg) message("  PASS  ", msg)
fail <- function(msg) { message("  FAIL  ", msg); stop(msg, call. = FALSE) }

check <- function(label, expr) {
  if (isTRUE(expr)) pass(label) else fail(label)
}

# Set a Shiny input via JS (works with module-namespaced IDs)
js_set <- function(app, id, value) {
  app$run_js(sprintf(
    "Shiny.setInputValue('%s', %s, {priority: 'event'})",
    id, jsonlite::toJSON(value, auto_unbox = TRUE)
  ))
}

# Click any element by CSS selector
js_click <- function(app, selector) {
  app$run_js(sprintf(
    "(function(){ var el = document.querySelector('%s'); if(el) el.click(); else throw new Error('not found: %s'); })()",
    selector, selector
  ))
}

wait_tab <- function(app, tab, timeout = 20000) {
  deadline <- Sys.time() + timeout / 1000
  repeat {
    app$wait_for_idle(timeout = 2000)
    current <- tryCatch(app$get_value(input = "app_tabs"), error = function(e) NULL)
    if (identical(current, tab)) return(invisible(tab))
    if (Sys.time() > deadline) stop("Timed out waiting for tab: ", tab, call. = FALSE)
    Sys.sleep(0.4)
  }
}

wait_js <- function(app, js_expr, timeout = 30000) {
  app$wait_for_js(js_expr, timeout = timeout)
}

# ── Launch app ────────────────────────────────────────────────────────────────
message("\n[1] Launching app...")
app <- AppDriver$new(
  app_dir      = app_dir,
  name         = "dataganger-harness",
  timeout      = 25000,
  load_timeout = 25000,
  options      = list(shiny.launch.browser = FALSE),
  height       = 900,
  width        = 1400
)
on.exit(app$stop(), add = TRUE)
pass("App launched")

# ── Step 1: Upload — load individual sample ───────────────────────────────────
message("\n[2] Upload screen — load individual sample...")

# Set select value then fire change event, then click the button
app$run_js("
  var sel = document.querySelector('#upload-sample_dataset');
  sel.value = 'individual';
  sel.dispatchEvent(new Event('change'));
  Shiny.setInputValue('upload-sample_dataset', 'individual');
")
Sys.sleep(0.4)
app$run_js("document.querySelector('#upload-load_sample').click()")
Sys.sleep(0.5)

wait_tab(app, "roles", timeout = 20000)
pass("Auto-advanced to Roles after sample load")

action_bar <- app$get_html(".action-bar")
check("Action bar shows 'file loaded'", grepl("file loaded", action_bar, fixed = TRUE))

# ── Step 2: Roles — confirm ───────────────────────────────────────────────────
message("\n[3] Roles screen — confirm roles...")
app$run_js("document.querySelector('#roles-confirm').click()")
Sys.sleep(0.5)

wait_tab(app, "purpose", timeout = 15000)
pass("Auto-advanced to Spec after roles confirmed")

# ── Step 3: Spec — choose teaching, confirm ───────────────────────────────────
message("\n[4] Spec screen — select purpose and confirm...")
app$run_js("
  var r = document.querySelector('input[name=\"synthesis_controls-purpose_group\"][value=\"teaching\"]');
  if (r) { r.checked = true; r.dispatchEvent(new Event('change')); }
  Shiny.setInputValue('synthesis_controls-purpose_group', 'teaching');
")
Sys.sleep(0.4)
app$run_js("document.querySelector('#synthesis_controls-confirm').click()")
Sys.sleep(0.5)

wait_tab(app, "generate", timeout = 15000)
pass("Auto-advanced to Generate after spec confirmed")

# ── Step 4: Generate — run synthesis ─────────────────────────────────────────
message("\n[5] Generate screen — run synthesis...")
app$run_js("document.querySelector('#generate-generate').click()")
Sys.sleep(0.5)

# Wait for synthesis output — the Compare button only renders post-synthesis
wait_js(
  app,
  "document.getElementById('generate-go_compare') !== null",
  timeout = 45000
)
pass("Synthesis complete — Compare button rendered")

# Check stats grid
stats_html <- app$get_html("body")
check("Stats grid contains ROWS", grepl("ROWS", stats_html, fixed = TRUE))
check("Stats grid contains DURATION", grepl("DURATION", stats_html, fixed = TRUE))

# ── Step 5: Navigate to Compare ───────────────────────────────────────────────
message("\n[6] Navigate to Compare...")
app$run_js("document.querySelector('#generate-go_compare').click()")
Sys.sleep(0.5)

wait_tab(app, "compare", timeout = 15000)
pass("Navigated to Compare screen")

page_html <- app$get_html("body")
check("Compare screen rendered (has pane content)", grepl("pane|compare|utility", page_html, ignore.case = TRUE))

# ── Step 6: Navigate to Export ────────────────────────────────────────────────
message("\n[7] Navigate to Export...")
js_set(app, "nav_go", "export")
Sys.sleep(0.3)

wait_tab(app, "export", timeout = 15000)
pass("Navigated to Export screen")

export_html <- app$get_html("body")
check("Download button present", grepl("download|Download", export_html))

# ── Summary ───────────────────────────────────────────────────────────────────
message("\n=== All checks passed ===\n")
