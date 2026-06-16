# CODEX IMPLEMENTATION HANDOFF — synthpop Objective Routing

## Handoff control block

- **Project:** dataganger (R package)
- **Repo root:** `/home/yeli/repos/dataganger`
- **Platform:** WSL2 Ubuntu 24.04 (PHO-000108 / knowhere)
- **Target agent/tool:** OpenAI Codex
- **Authorization:** MAY MODIFY FILES WITHIN SCOPE
  - In-scope files are listed per task below. Ordinary edits inside that scope need no per-edit approval.
  - **Out of scope — require separate Lennon approval:** scope expansion, `git commit`, `git push`, deletes, dependency changes (e.g. moving synthpop from Suggests to Imports), `DESCRIPTION` version bumps, deployments, secrets, any destructive action.
- **Source of truth:** `docs/superpowers/specs/2026-06-15-synthpop-integration-design.md` (read it first — this handoff implements it).
- **Prior phase (already merged):** manual `engine =` flag + `synthesize_synthpop()` wrapper. See `.hermes/plans/2026-06-15_synthpop-backend.md`. Do **not** redo that work.

---

## Goal

Make synthpop the **objective-routed fidelity engine**: the engine is derived automatically
from `spec$preserve_correlations`, the user never picks it, and absence of synthpop degrades
gracefully instead of crashing. Then fold synthpop's disclosure numbers into the privacy
panel and make the `model_prototype` UI posture honest.

**80/20 scope.** Deferred (do NOT implement): synthpop `rules`/`rvalues`, the
`lm.synds`/`glm.synds` inference workflow, per-column `method` vectors, predictor-matrix
density tuning, `semicont`/`numtocat` continuous handling. These are explicit non-goals.

---

## Conventions (do not break)

- `cli::cli_abort()` / `cli::cli_warn()` for all errors and warnings — never `stop()`/`warning()`.
- No non-ASCII characters in R source (use `\uXXXX` escapes — see existing `R/mod-synthesis-controls.R`).
- `synthpop` stays in **Suggests**, never Imports.
- `%||%` is defined in `R/utils.R` — use freely.
- All synthpop tests guarded by `skip_if_not_installed("synthpop")`.
- `\dontrun{}` on examples that run the pipeline or write to disk.

---

## Key reconciliation point — read before Task 2

`internal_hifi` currently **aborts**. In `R/synthesize-data.R` (~line 40):

```r
if (spec$engine_required == "hifi") {
  cli::cli_abort("The hifi engine is reserved for v0.2.", ...)
}
```

`engine_required` is set by `engine_for(level, purpose)` (`R/synth-spec.R:93`, defined ~line
308: `"hifi"` when `level == "hifi" || purpose == "internal_hifi"`).

The design routes `internal_hifi` (preserve_correlations = `"high"`) to **synthpop**, not an
abort. So this guard must change: `internal_hifi` should now resolve to the synthpop path (or
the graceful fallback when synthpop is absent), NOT abort. Treat `engine_required == "hifi"`
as "wants the fidelity engine," which is now synthpop. Confirm with Lennon if you read the
intent differently — but the design table (spec section 1) is explicit: internal_hifi -> synthpop.

`preserve_correlations` preset values (from `R/synth-spec.R`):

| Objective | preserve_correlations | Target engine |
|---|---|---|
| teaching | none | internal |
| safer_external | none | internal |
| ai_programming | low | internal |
| shiny_prototype | low | internal |
| model_prototype | moderate | **synthpop** |
| internal_hifi | high | **synthpop** |

---

## Task 1 — `engine_from_correlations()` + tests

**Scope:** `R/synth-spec.R` (or a new `R/engine-routing.R`), `tests/testthat/test-engine-routing.R` (create).

Add a small pure helper:

```r
engine_from_correlations <- function(spec) {
  pc <- spec$preserve_correlations %||% "none"
  if (pc %in% c("moderate", "high")) "synthpop" else "internal"
}
```

Binary mapping only — no density tuning (the 80/20 simplification).

Tests (no synthpop dependency needed — pure logic):
- `none`, `low` -> `"internal"`.
- `moderate`, `high` -> `"synthpop"`.
- `NULL`/missing `preserve_correlations` -> `"internal"`.
- Each objective preset routes to the expected engine (build via `synth_spec(purpose = ...)`
  and assert `engine_from_correlations(spec)`).

Run: `Rscript -e 'devtools::test(filter = "engine-routing")'`

---

## Task 2 — Derived routing + graceful fallback in `synthesize_data()`

**Scope:** `R/synthesize-data.R`, `tests/testthat/test-synthesize-data.R`.

Change the effective-engine resolution (currently `R/synthesize-data.R:35-38`):

```r
spec_engine <- spec[["engine", exact = TRUE]]
explicit    <- engine %||% spec_engine          # NULL when nothing was asked for
engine      <- explicit %||% engine_from_correlations(spec)
engine      <- match.arg(engine, c("internal", "marginal", "synthpop"))
if (engine == "marginal") engine <- "internal"
```

Reconcile the `engine_required == "hifi"` abort (see reconciliation note above): remove the
hard abort; let `internal_hifi` flow to the synthpop path.

**Graceful fallback** — when the engine was *derived* (no explicit request) and synthpop is
absent: warn once and fall back to internal. When the engine was *explicitly* requested by
name, keep the existing hard error (the `requireNamespace()` guard inside
`synthesize_synthpop()`):

```r
if (engine == "synthpop" && is.null(explicit) &&
    !requireNamespace("synthpop", quietly = TRUE)) {
  cli::cli_warn(
    "Install {.pkg synthpop} for full-fidelity synthesis; using the marginal engine for now."
  )
  engine <- "internal"
}
```

Safe by construction: falling back only *lowers* fidelity, never raises disclosure risk.

Tests (add to `test-synthesize-data.R`):
- Derived synthpop + synthpop installed -> output carries `attr(syn, "engine") == "synthpop"`
  (guard `skip_if_not_installed("synthpop")`).
- Derived synthpop + synthpop absent -> warning emitted AND internal output returned, no error
  (`skip_if(requireNamespace("synthpop", quietly = TRUE))`).
- Explicit `engine = "synthpop"` + synthpop absent -> error with install prompt (existing test,
  keep).
- `model_prototype` / `internal_hifi` specs route to synthpop; `teaching` routes to internal.
- Explicit `engine = "internal"` overrides a synthpop-implying spec.

Run: `Rscript -e 'devtools::test(filter = "synthesize-data")'`

---

## Task 3 — `spec_to_synthpop_args()` translator + wire into `synthesize_synthpop()`

**Scope:** `R/synthesize-synthpop.R`, `tests/testthat/test-synthesize-synthpop.R`.

Extract a thin, isolated translator so all synthpop knowledge lives in one testable place:

```r
spec_to_synthpop_args <- function(spec, roles, data) {
  excl <- synthpop_excluded_cols(roles)          # ID-candidate + free-text (already logic in wrapper)
  work <- data[, !names(data) %in% excl, drop = FALSE]
  args <- list(data = work, print.flag = FALSE)
  if (!is.null(spec$seed)) args$seed <- as.integer(spec$seed)
  if (!is.null(spec$n))    args$k    <- as.integer(spec$n)
  # high-fidelity continuous privacy: density smoothing on genuine continuous numerics only
  num_cont <- names(work)[vapply(work, is_continuous_numeric, logical(1))]
  if (length(num_cont)) {
    sm <- setNames(rep("density", length(num_cont)), num_cont)
    args$smoothing <- sm
  }
  args
}
```

- `smoothing = "density"` only on **genuine continuous** numerics — guard integer / bounded
  columns (open risk in spec section "Open risks": density smoothing can push values
  out-of-range). Implement `is_continuous_numeric()` conservatively (numeric, non-integer, more
  than a small number of distinct values); restrict if it produces out-of-range values.
- Refactor the existing exclusion logic in `synthesize_synthpop()` to call this translator so
  there is a single source of truth. Keep the `requireNamespace()` guard.

Tests:
- `spec_to_synthpop_args()` sets `k` from `spec$n`, `seed` from `spec$seed`.
- Excludes ID-candidate and free-text columns (reuse `detect_roles()` fixture).
- `smoothing` present and `"density"` for continuous numerics; absent/empty for pure-integer
  data.
- Existing wrapper tests still pass (reproducibility, n rows, abort when all columns excluded).

Run: `Rscript -e 'devtools::test(filter = "synthesize-synthpop")'`

---

## Task 4 — disclosure folding into the privacy panel (synthpop path only)

**Scope:** `R/privacy-check.R` (+ wherever the synthpop branch assembles its result in
`R/synthesize-data.R`), `tests/testthat/test-privacy-check.R` (or new test file).

On the **synthpop path only**, after generation compute `synthpop::disclosure()` on the
**role-flagged quasi-identifier columns** (NOT all columns — keeps it fast on wide data) and
fold identity/attribute risk numbers into the existing privacy panel.

- `privacy_check()` stays the primary, cross-engine panel; disclosure *augments* it on the
  synthpop path, does not replace it.
- Internal marginal path: untouched (marginal independence already caps re-identification).
- Guard for cost: scope to flagged columns; note the open risk (row-sampling fallback) in a
  code comment if you add one.

Tests (guard `skip_if_not_installed("synthpop")`):
- synthpop-path privacy panel includes disclosure numbers.
- internal-path privacy panel does NOT include them.

Run: `Rscript -e 'devtools::test(filter = "privacy")'`

---

## Task 5 — honest UI posture for `model_prototype`

**Scope:** `R/mod-synthesis-controls.R`, `R/synth-spec.R` (the `model_prototype` warning at
~line 216), relevant snapshot/UI tests.

`model_prototype` is now genuinely relationship-aware, so the UI must stop understating risk:

- `R/mod-synthesis-controls.R` ~line 280-282: replace the `does_not_preserve` /
  `privacy_caution = "v0.1 uses marginal synthesis only..."` copy. State that relationships
  ARE now preserved; add a one-line privacy caution.
- ~line 360 `"Does not preserve (v0.1):"` block: update accordingly.
- Move the `identifiability` meter (~line 132) up to reflect higher identifiability for
  `model_prototype`.
- `R/synth-spec.R` ~line 216: the runtime warning ("Relationship-aware synthesis is planned
  for a future release. In v0.1, model_prototype uses marginal synthesis...") is now false —
  remove or rewrite it to reflect synthpop routing.
- **No new risk-acknowledgment gate** — that stays `internal_hifi`-only. Only the *displayed
  posture* changes.

Update any UI snapshot tests that capture this copy.

---

## Task 6 — acknowledgment + manual guidance

**Scope:** `README`, `NEWS`/`NEWS.md`, package docs, vignette/manual, bundle/diagnostic
provenance writer.

- Add the canonical citation to README / NEWS / package docs:
  > Nowok B, Raab GM, Dibben C (2016). "synthpop: Bespoke Creation of Synthetic Data in R."
  > *Journal of Statistical Software*, 74(11), 1-26. doi:10.18637/jss.v074.i11
- Add a short **"Synthesis engines"** section to the manual/vignette (text in spec section 6).
- Provenance: when synthpop runs, agent bundle + diagnostic export record `engine = "synthpop"`
  plus the citation. (`attr(syn, "engine")` is already set — ensure it propagates into the
  written manifest/provenance.)

---

## Task 7 — final verification (do NOT commit/push — that needs Lennon approval)

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check(document = FALSE, error_on = "warning")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP <n> | PASS <N> ]` and R CMD check `0 errors | 0 warnings |
1 note` (pre-existing Chrome note; clock/CRAN-feasibility notes under WSL are DNS-isolation
false positives — set `_R_CHECK_SYSTEM_CLOCK_=0`).

When green, **stop and report back to Lennon** with the test/check summary and a proposed
commit plan. Do not commit, push, or change `DESCRIPTION`/dependencies without explicit
approval.

---

## Definition of done

- Engine derived from objective; user never picks one; explicit `engine=` still overrides.
- `internal_hifi` and `model_prototype` route to synthpop (no abort).
- synthpop absent + derived path -> warn + internal; explicit `engine="synthpop"` -> install error.
- `spec_to_synthpop_args()` isolates all synthpop knowledge; density smoothing only on safe
  continuous numerics.
- Disclosure numbers in privacy panel on synthpop path only.
- `model_prototype` UI posture honest; no false "future release" copy remains.
- synthpop credited in docs + provenance; stays in Suggests.
- Full suite + R CMD check green. Nothing committed/pushed without approval.
