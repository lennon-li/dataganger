# Manual browser walkthrough: the 0.8.0 disclosure-risk brief on the Export step.
#
# Not run by devtools::test(). Follows verify-app-browser.R: shinytest2::AppDriver
# cannot navigate to its own subprocess on this Linux setup (see that file's
# header), so this drives the installed app with a standalone chromote session:
# callr::r_bg() serves the app, the port is polled until it answers, then a raw
# ChromoteSession walks the app from a cold start to Export:
#
#   Load sample -> column triage -> Objective -> Configure (answer every column,
#   mark one sensitive) -> Generate (real synthesis, polled) -> Compare -> Export
#
# Assertions (printed as PASS/FAIL, "%-40s %s" style):
#   1. a modal is present in the DOM once the Export step is reached
#   2. the modal reports the minimum group size, blanked rows, exact synthetic
#      reproductions of real records, and how many expose a sensitive value
#   3. jargon scrub: the RENDERED modal text (innerText, not outerHTML -- CSS
#      comments in inst/app/www/shiny-app.css must not cause false leaks)
#      contains no "k-anon", "k-anonymity", "quasi-identifier", "enforce_kanon",
#      or whole-word "QI"
#   4. the Export step was reached at all (the brief did not block navigation)
#
# Exit codes: 0 all checks pass; 1 one or more checks FAIL; 2 the walkthrough
# itself could not proceed (app/Chrome/step failure -- reported, not hidden).
#
# Usage, from the package root, against an INSTALLED dataganger (>= 0.8.0):
#   R CMD INSTALL . && Rscript tests/manual/verify-export-risk-modal.R
#
# STATUS AS COMMITTED -- INCOMPLETE. Do not read a silent run as a pass.
# Last run 2026-08-02 against 0.8.0 (feat/kanon-slider). It gets four steps in:
#
#   attestation answered            PASS
#   sample loaded, triaged          PASS
#   objective step reached          PASS
#   configure step reached          PASS
#   -> STOPS at "configure: answer landing for smoker" (exit 2)
#
# So none of assertions 1-4 above has ever actually been evaluated. The stall is
# in this harness's Configure loop, not a reproduced app defect: it sets each
# column's answer with Shiny.setInputValue and then polls the re-rendered table
# until the <select> reports the new value, and for "smoker" that poll times out
# at 20s. Unconfirmed suspicion: the row index is parsed out of the select's
# onchange attribute, and the table rebuilds after every answer, so the index
# can go stale mid-loop. apply_sensitive_change() (R/mod-roles.R:689) does
# accept "no" and clears the unset state, so the app side looks correct.
#
# Fixing the loop is the next step for anyone picking this up; until then this
# file is scaffolding, not evidence.

stopifnot(
  requireNamespace("chromote", quietly = TRUE),
  requireNamespace("shiny", quietly = TRUE),
  requireNamespace("callr", quietly = TRUE)
)
stopifnot("dataganger is not installed" = nzchar(system.file("app", package = "dataganger")))
stopifnot(
  "this walkthrough targets the 0.8.0 disclosure-risk brief" =
    packageVersion("dataganger") >= "0.8.0"
)

# --- reporting ---------------------------------------------------------------

checks <- list()
report <- function(name, ok) {
  checks[[name]] <<- isTRUE(ok)
  cat(sprintf("%-40s %s\n", name, if (isTRUE(ok)) "PASS" else "FAIL"))
  invisible(ok)
}
abort_walk <- function(step, detail = "") {
  cat(sprintf("\nWALKTHROUGH STOPPED at step: %s\n", step))
  if (nzchar(detail)) cat(detail, "\n")
  cat("This is a walkthrough failure, not an assertion result (exit 2).\n")
  quit(status = 2L)
}
snippet <- function(x, n = 900L) {
  x <- paste(x, collapse = " ")
  if (nchar(x) > n) paste0(substr(x, 1L, n), " [truncated]") else x
}

# --- serve the installed app --------------------------------------------------

port <- 5097L
url <- sprintf("http://127.0.0.1:%d/", port)
app_dir <- system.file("app", package = "dataganger")

server <- callr::r_bg(
  function(dir, port) {
    shiny::runApp(dir, port = port, host = "127.0.0.1", launch.browser = FALSE)
  },
  args = list(dir = app_dir, port = port)
)
on.exit(server$kill(), add = TRUE)

# The app pulls in bslib, DT and the full module tree before it serves.
deadline <- Sys.time() + 90
repeat {
  ok <- tryCatch(
    {
      con <- url(url); on.exit(close(con), add = FALSE); readLines(con, n = 1L)
      TRUE
    },
    error = function(e) FALSE
  )
  if (isTRUE(ok)) break
  if (!server$is_alive()) abort_walk("app start", paste0("app process died: ", server$read_all_output()))
  if (Sys.time() > deadline) abort_walk("app start", "app did not answer the port within 90s")
  Sys.sleep(2)
}

chromote::set_chrome_args(c(
  chromote::default_chrome_args(),
  "--no-sandbox",
  "--disable-dev-shm-usage"
))
b <- tryCatch(chromote::ChromoteSession$new(),
              error = function(e) abort_walk("chrome attach", conditionMessage(e)))
on.exit(b$close(), add = TRUE)

invisible(b$Page$navigate(url, timeout_ = 60))

evaluate <- function(js) {
  tryCatch(
    b$Runtime$evaluate(js, returnByValue = TRUE)$result$value,
    error = function(e) NA
  )
}
visible <- function(sel) {
  isTRUE(evaluate(sprintf(
    "(function(){var el=document.querySelector('%s'); return !!el && el.offsetParent !== null;})()",
    sel
  )))
}
click <- function(sel) {
  identical(evaluate(sprintf(paste0(
    "(function(){var el=document.querySelector('%s'); if(!el) return 'missing';",
    "el.scrollIntoView({block:'center'}); el.click(); return 'clicked';})()"
  ), sel)), "clicked")
}
wait_for <- function(pred, timeout_s, what, detail_fun = NULL) {
  deadline <- Sys.time() + timeout_s
  repeat {
    v <- tryCatch(pred(), error = function(e) FALSE)
    if (isTRUE(v)) return(invisible(TRUE))
    if (Sys.time() > deadline) {
      detail <- if (is.function(detail_fun)) tryCatch(detail_fun(), error = function(e) "") else ""
      abort_walk(what, detail)
    }
    Sys.sleep(0.7)
  }
}

dom_state <- function() {
  txt <- evaluate(paste0(
    "(function(){var lines=[];",
    "var panes=document.querySelectorAll('.tab-pane');",
    "for(var i=0;i<panes.length;i++){if(!panes[i].classList.contains('active'))continue;",
    "lines.push('active pane markers: '+['#upload-load_sample','#synthesis_controls-confirm_objective',",
    "'#synthesis_controls-confirm','#generate-generate','#generate-go_compare','#compare-go_export',",
    "'#export-download'].filter(function(s){return panes[i].querySelector(s);}).join(', ')||'none');}",
    "var modals=document.querySelectorAll('.modal .modal-content');",
    "if(modals.length){lines.push('modal text: '+modals[modals.length-1].innerText.slice(0,200));}",
    "var notif=document.querySelector('.shiny-notification');",
    "if(notif){lines.push('notification: '+notif.innerText.slice(0,200));}",
    "return lines.join('\\n')||'no active pane / no modal / no notification';})()"
  ))
  paste0("--- DOM state ---\n", paste(txt, collapse = "\n"), "\n-----------------")
}

# Shiny connects a few beats after the HTML loads; the attestation modal is the
# first interactive surface (app_guardrail_server, easyClose = FALSE).
wait_for(
  function() isTRUE(evaluate("window.Shiny !== undefined && !!Shiny.shinyapp && Shiny.shinyapp.isConnected()")),
  60, "shiny websocket connect", dom_state
)
wait_for(function() visible("#guardrail-agree"), 60, "attestation modal", dom_state)
click("#guardrail-agree")
report("walk: attestation answered", TRUE)

# --- upload: load the built-in individual sample -------------------------------

wait_for(function() visible("#upload-load_sample"), 30, "upload step", dom_state)
click("#upload-load_sample")

# Column triage modal (mod_column_filter_server). Keep the defaults: the
# id-shaped column is pre-suggested for Drop, which also keeps the fail-safe
# check from flagging it. The Continue button is the delegate-handled .cf-apply.
wait_for(function() visible(".cf-apply"), 60, "column triage modal", dom_state)
click(".cf-apply")
report("walk: sample loaded, triaged", TRUE)

# --- objective -----------------------------------------------------------------
# Auto-advance after triage unless the fail-safe flags something first; if it
# does, confirm-and-keep (fail-safe is advisory and its modal blocks the way).
wait_for(function() {
  if (visible("#guardrail-confirm_keep_flagged")) {
    click("#guardrail-confirm_keep_flagged")
    Sys.sleep(1)
  }
  visible("#synthesis_controls-confirm_objective")
}, 120, "objective step", dom_state)
report("walk: objective step reached", TRUE)
click("#synthesis_controls-confirm_objective")

# --- configure ------------------------------------------------------------------
wait_for(function() visible("#synthesis_controls-confirm"), 60, "configure step", dom_state)
report("walk: configure step reached", TRUE)

roles_rows_js <- paste0(
  "(function(){var out=[];",
  "var rows=document.querySelectorAll('#roles-roles_table table tbody tr');",
  "rows.forEach(function(tr){var cells=tr.querySelectorAll('td');",
  "if(cells.length<3)return;",
  "var s=cells[1].querySelector('span');",
  "var rec={name: s ? s.innerText.trim() : cells[1].innerText.trim()};",
  "['q1','q2'].forEach(function(key,i){var sel=cells[2].querySelectorAll('select')[i];",
  "if(!sel){rec[key+'_row']=null;rec[key+'_val']=null;return;}",
  "var m=(sel.getAttribute('onchange')||'').match(/row:\\s*(\\d+)/);",
  "rec[key+'_row']=m?parseInt(m[1],10):null; rec[key+'_val']=sel.value;});",
  "out.push(rec);});return out;})()"
)
set_role_answer <- function(input_suffix, row_idx, value) {
  isTRUE(evaluate(sprintf(
    "Shiny.setInputValue('roles-%s', {row: %d, value: '%s'}, {priority:'event'}); true",
    input_suffix, row_idx, value
  )))
}
wait_row_answered <- function(name, field, expected) {
  wait_for(function() {
    rows <- evaluate(roles_rows_js)
    if (!is.list(rows)) return(FALSE)
    hit <- Filter(function(r) identical(r$name, name), rows)
    length(hit) > 0 && identical(hit[[1]][[field]], expected)
  }, 20, sprintf("configure: answer landing for %s", name), dom_state)
}

# Wait for the roles table to render (role detection runs after triage).
wait_for(function() {
  rows <- evaluate(roles_rows_js)
  is.list(rows) && length(rows) > 0
}, 120, "roles table render", dom_state)

# The question-2 axis MUST get at least one "yes": the brief then reports its
# worst case (exact reproductions exposing a sensitive value). Plan marks income
# sensitive; age/sex/education become combination (quasi) columns so k-anonymity
# has something to enforce; any unexpected extra column defaults to none/no.
plan <- list(
  age       = c(ids = "combination", sens = "no"),
  sex       = c(ids = "combination", sens = "no"),
  education = c(ids = "combination", sens = "no"),
  income    = c(ids = "none",        sens = "yes"),
  smoker    = c(ids = "none",        sens = "no"),
  bmi       = c(ids = "none",        sens = "no")
)
default_answer <- c(ids = "none", sens = "no")

rows <- evaluate(roles_rows_js)
names_seen <- vapply(rows, function(r) r$name, character(1))
targets <- lapply(names_seen, function(nm) plan[[nm]] %||% default_answer)
names(targets) <- names_seen
if (!any(vapply(targets, function(t) identical(t[["sens"]], "yes"), logical(1)))) {
  # Sample changed: force the worst-case condition onto the first column so the
  # sensitive-exposure surface is still exercised.
  targets[[1]][["sens"]] <- "yes"
}

# One change at a time, then poll until the re-rendered table reflects it.
# Firing all answers at once is racy: each change rebuilds #roles-roles_table,
# so a second dispatch against the stale DOM node would get lost.
for (nm in names(targets)) {
  tgt <- targets[[nm]]
  cur <- Filter(function(r) identical(r$name, nm), evaluate(roles_rows_js))[[1]]
  if (!identical(cur$q1_val, tgt[["ids"]])) {
    stopifnot(!is.null(cur$q1_row))
    set_role_answer("identifies_change", cur$q1_row, tgt[["ids"]])
    wait_row_answered(nm, "q1_val", tgt[["ids"]])
  }
  cur <- Filter(function(r) identical(r$name, nm), evaluate(roles_rows_js))[[1]]
  if (!identical(cur$q2_val, tgt[["sens"]])) {
    stopifnot(!is.null(cur$q2_row))
    set_role_answer("sensitive_change", cur$q2_row, tgt[["sens"]])
    wait_row_answered(nm, "q2_val", tgt[["sens"]])
  }
}

rows <- evaluate(roles_rows_js)
all_answered <- all(vapply(
  rows,
  function(r) nzchar(r$q1_val %||% "") && nzchar(r$q2_val %||% ""),
  logical(1)
))
sensitive_marked <- any(vapply(rows, function(r) identical(r$q2_val, "yes"), logical(1)))
report("walk: all columns answered (Q1+Q2)", all_answered)
report("walk: sensitive column marked (Q2)", sensitive_marked)
if (!all_answered || !sensitive_marked) {
  abort_walk("configure: answers did not stick", dom_state())
}

click("#synthesis_controls-confirm")

# --- generate --------------------------------------------------------------------
# Confirm auto-advances when the spec is valid; a notification + the disclosure
# gate banner appear if any answer is missing.
wait_for(function() visible("#generate-generate"), 45, "generate step (spec confirm)", dom_state)
report("walk: spec confirmed, generate step", TRUE)

click("#generate-generate")
# Real synthesis (synthpop when installed) in a background process; the module
# polls it every 300ms and swaps the header CTA to "Continue to Compare" when
# done. Poll that CTA instead of sleeping. Generous 360s budget: no fixed sleeps
# are used anywhere on this path, so this is a ceiling, not a wait.
wait_for(function() visible("#generate-go_compare"), 360, "synthesis completion", dom_state)
report("walk: synthesis finished", TRUE)

# --- compare -----------------------------------------------------------------------
click("#generate-go_compare")
wait_for(function() visible("#compare-go_export"), 45, "compare step", dom_state)
report("walk: compare step reached", TRUE)
# The compare body renders on arrival (outputs are suspended while hidden).
wait_for(function() {
  txt <- evaluate("(document.querySelector('#compare-compare_body')||{innerText:''}).innerText")
  is.character(txt) && nzchar(txt) && !grepl("Generate synthetic data first", txt, fixed = TRUE)
}, 120, "compare body render", dom_state)

# --- export: the disclosure-risk brief ----------------------------------------------
click("#compare-go_export")
export_reached <- tryCatch(
  {
    wait_for(function() visible("#export-download"), 45, "export step", dom_state)
    TRUE
  },
  error = function(e) FALSE
)
report("export step reached", export_reached)

modal_present <- FALSE
modal_text <- ""
if (export_reached) {
  modal_present <- tryCatch(
    {
      wait_for(function() {
        isTRUE(evaluate("!!document.querySelector('.modal .modal-content')"))
      }, 30, "disclosure-risk modal on Export", dom_state)
      TRUE
    },
    error = function(e) FALSE
  )
}
report("modal present on Export", modal_present)

if (modal_present) {
  # innerText of the rendered modal -- not outerHTML -- so markup or CSS
  # comments can never count as a leak.
  modal_text <- evaluate(paste0(
    "(function(){var ms=document.querySelectorAll('.modal');",
    "return ms.length ? ms[ms.length-1].innerText : '';})()"
  ))
  if (!is.character(modal_text)) modal_text <- ""
}

report(
  "modal reports minimum group size",
  grepl("at least [0-9]+ times", modal_text)
)
report(
  "modal reports rows blanked",
  grepl("row\\(s\\) .{0,40}blanked", modal_text) ||
    grepl("No rows needed to be blanked", modal_text, fixed = TRUE)
)
report(
  "modal reports exact reproductions",
  grepl("[0-9]+ synthetic row\\(s\\) reproduce a real record exactly", modal_text)
)
report(
  "modal reports sensitive exposures",
  grepl("expose a value you marked sensitive", modal_text, fixed = TRUE)
)

# Jargon scrub. Whole-word QI is matched separately from the fixed substrings;
# "k-anon" deliberately subsumes "k-anonymity".
jargon_hits <- character(0)
for (term in c("k-anon", "quasi-identifier", "enforce_kanon")) {
  if (grepl(term, modal_text, fixed = TRUE, ignore.case = TRUE)) {
    jargon_hits <- c(jargon_hits, term)
  }
}
if (grepl("\\bQI\\b", modal_text, ignore.case = TRUE)) {
  jargon_hits <- c(jargon_hits, "QI (whole word)")
}
report("jargon scrub (modal innerText)", length(jargon_hits) == 0)
if (length(jargon_hits) > 0) {
  for (term in jargon_hits) {
    m <- regexpr(paste0("(?i)", if (term == "QI (whole word)") "\\bQI\\b" else term),
                 modal_text, perl = TRUE)
    ctx <- if (m > 0) {
      s <- max(1, m - 60)
      e <- min(nchar(modal_text), m + attr(m, "match.length") + 60)
      substr(modal_text, s, e)
    } else "(match not re-located)"
    cat(sprintf("  offending term %-20s context: ...%s...\n", term, ctx))
  }
}

cat(sprintf("\nmodal title present: %s\n", grepl("Disclosure risk of this bundle", modal_text, fixed = TRUE)))
cat(sprintf("modal text (truncated):\n%s\n", snippet(modal_text)))

if (!all(unlist(checks))) {
  cat(sprintf("\n%d of %d checks failed.\n", sum(!unlist(checks)), length(checks)))
  quit(status = 1L)
}
cat(sprintf("\nall %d checks passed.\n", length(checks)))
