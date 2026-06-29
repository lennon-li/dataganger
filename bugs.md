# DataGangeR internal consistency audit

This file records consistency problems found during a repository audit on 2026-06-28. It is intended as a Codex handoff: fix the issues, add/adjust tests, then remove or archive this file when resolved.

## Scope reviewed

Reviewed the package-facing docs and main implementation paths:

- `README.md`
- `DESCRIPTION`
- `NAMESPACE`
- `_pkgdown.yml`
- `NEWS.md`
- `R/synth-spec.R`
- `R/synthesize-data.R`
- `R/detect-roles.R`
- `R/disclosure-helpers.R`
- `R/cli.R`
- `R/mod-roles.R`
- `R/mod-generate.R`
- `R/run-synthesis-async.R`
- `R/export-synthetic.R`
- `R/privacy-check.R`
- `R/synthesize-marginal.R`
- `R/synth-helpers.R`

## P0: Configure gate is UI-only; generation can proceed with unanswered privacy questions

### Problem

The Configure page displays a gate saying that columns still need answers before the user can generate, but the server path does not enforce that gate.

Current behavior:

- `mod_roles.R` counts unset `identifies` values and renders: `N columns still need an answer before you can generate.`
- `observeEvent(input$confirm, ...)` still confirms roles without checking whether any eligible column is unanswered.
- `mod_generate.R` starts generation if `state$raw_data` and `state$spec` exist; it does not validate whether `state$roles` is complete.
- `run_synthesis_pipeline()` also does not validate role completeness.

This contradicts the human-gated privacy model. It also means a user can see a warning saying generation is blocked while the backend still permits generation.

### Proposed fix

Add a single internal helper, for example:

```r
roles_ready_for_generation <- function(roles) {
  if (is.null(roles) || !"identifies" %in% names(roles)) return(FALSE)
  eligible <- rep(TRUE, nrow(roles))
  if ("simulation" %in% names(roles)) {
    eligible <- !(roles$simulation %in% c("drop", "pass_through"))
    eligible[is.na(eligible)] <- TRUE
  }
  all(!(is.na(roles$identifies[eligible]) | !nzchar(roles$identifies[eligible])))
}
```

Then enforce it in all relevant paths:

1. `mod_roles.R` confirm button: do not increment `roles_confirmed` if not ready; show a notification.
2. `mod_generate.R` generate/regenerate path: refuse generation if not ready.
3. `run_synthesis_pipeline()` or `synthesize_data()` if called from app with roles: abort if `roles` has incomplete disclosure axes unless explicitly bypassed. Prefer placing this at the pipeline/app layer so scripted API remains flexible, or add an argument if needed.

### Tests to add

- A unit test for `roles_ready_for_generation()`:
  - no roles -> `FALSE`
  - one unset eligible column -> `FALSE`
  - unset but `simulation == "drop"` -> `TRUE`
  - unset but `simulation == "pass_through"` -> probably `TRUE` only if this is intended; otherwise require a privacy answer even for pass-through because real values are exported.
- A Shiny server test or module test that `confirm` does not advance when roles are incomplete.
- A generation-path test that incomplete roles produce a clear error or warning.

## P0: CLI analytics purpose is impossible/incomplete because risk acknowledgement is not exposed

### Problem

`synth_spec(purpose = "analytics")` requires `acknowledge_risk = TRUE`, but the CLI does not expose this:

- `dataganger spec --purpose analytics --out spec.yaml` calls `synth_spec(purpose = purpose)` with no acknowledgement.
- `cli_read_spec_yaml()` does not allow `acknowledge_risk` or `acknowledged_risk` in YAML.
- `cli_cmd_synthesize()` reconstructs a hardened spec but also does not pass `acknowledge_risk`.

So the analytics objective is documented as available, but the CLI cannot cleanly create or consume it.

### Proposed fix

Add CLI support for risk acknowledgement:

1. Update `cli_print_help()`:
   - `spec --purpose <purpose> --out <spec.yaml> [--acknowledge-risk true|false]`
   - or a flag-style option if the parser is extended to support boolean flags.
2. Update `cli_cmd_spec()` to parse acknowledgement and pass `acknowledge_risk = TRUE` when requested.
3. Update `cli_read_spec_yaml()` to allow `acknowledge_risk` and/or `acknowledged_risk`.
4. Update `cli_cmd_synthesize()` when reconstructing `hardened_spec` to preserve the acknowledgement.
5. Make YAML naming consistent. Prefer public input field `acknowledge_risk`, but preserve emitted/internal `acknowledged_risk` if needed.

### Tests to add

- `dataganger_cli(c("spec", "--purpose", "analytics", "--out", tmp, "--acknowledge-risk", "true"), quit = FALSE)` returns 0 and writes YAML.
- Analytics YAML with acknowledgement can be used by `synthesize`.
- Analytics without acknowledgement still fails with a clear message.

## P1: README tells users to edit `engine` in YAML, but CLI YAML reader ignores `engine`

### Problem

README CLI section says:

```sh
# Edit spec.yaml if needed: set seed, engine/name_strategy overrides,
# and disclosure_roles: <column>: <direct|quasi|sensitive|none>.
```

But `cli_read_spec_yaml()` only allows:

```r
c("level", "n", "name_strategy", "seed", "preserve_correlations",
  "coarsen_dates", "merge_rare", "free_text_strategy",
  "rare_level_min_n", "preserve_missingness", "k_anon")
```

It omits `engine`, so `engine:` in `spec.yaml` is ignored. The `synthesize` command separately supports `--engine`, but that conflicts with the README's YAML contract.

### Proposed fix

Either option is acceptable; prefer Option A.

Option A: make README true.

- Add `engine` to the allowed YAML override fields.
- Pass it into `synth_spec()`.
- Preserve `engine` when hardening/reconstructing the spec.
- Keep `--engine` as a command-line override with higher precedence than YAML.

Option B: make code contract explicit.

- Remove `engine` from the README YAML-edit instruction.
- Say engine is overridden with `dataganger synthesize ... --engine internal|synthpop`.

### Tests to add

- YAML with `engine: internal` results in internal engine unless `--engine synthpop` overrides it.
- README CLI example remains executable.

## P1: Role model documentation is split between old single-role model and new two-axis model

### Problem

Current implementation clearly uses two privacy axes:

- `identifies`: `none`, `combination`, `direct`
- `sensitive`: logical

`disclosure_role` is now a derived projection for compatibility with existing synthesis/export/CLI code.

However, some docs and roxygen text still describe the old single `disclosure_role` model. Examples:

- `detect_roles()` return docs focus on `disclosure_role` and say `direct` and `sensitive` are the only auto-assigned values.
- `_pkgdown.yml` says role detection covers disclosure axes, but also references `disclosure_roles:` spec in a way that reads like the current primary model.
- NEWS mixes versions of this story.

Also note: `dg_seed_disclosure()` now seeds suggestions beyond just direct/sensitive:

- `date` -> `quasi`
- `numeric` -> `none`
- `logical` -> `none`

So the docs saying only `direct` and `sensitive` are auto-assigned are stale or at least incomplete.

### Proposed fix

Make the two-axis model the source of truth everywhere:

1. Update `detect_roles()` roxygen:
   - Document `identifies`, `sensitive`, `disclosure_role`, `simulation`.
   - State that `disclosure_role` is derived compatibility metadata.
   - Clarify what is auto-suggested versus what must be reviewed.
2. Update `_pkgdown.yml` wording:
   - Avoid implying `disclosure_roles:` is the primary user-facing model.
   - Say CLI still accepts `disclosure_roles:` as compatibility mapping, or add a new two-axis CLI mapping if implemented.
3. Update README CLI wording to explain whether CLI users should edit `disclosure_roles:` or a new `roles.yaml` two-axis file.

### Tests to add

- Test `dg_axes_to_role()` and `dg_role_to_axes()` round trips for supported values.
- Test `dg_seed_disclosure()` behavior is intentional and documented.
- Test generated role outputs include expected columns.

## P1: Export bundle README overclaims privacy safety

### Problem

Top-level README correctly says synthetic data reduces direct disclosure risk but does not replace a formal privacy assessment.

But bundle README generated by `render_bundle_readme()` says:

> This is synthetic data, safe to share with AI coding tools.

That overclaims relative to the package's own design principle: synthetic output reduces risk but is not guaranteed safe.

### Proposed fix

Change this wording to something like:

> This is synthetic data designed to reduce direct disclosure risk for AI coding workflows. Use it to build and test code, but review the privacy report and your local data-governance requirements before sharing externally.

Also check `inst/templates/ai-readme.md` for similar overclaims.

### Tests to add

- Snapshot/unit test for `render_bundle_readme()` to ensure it does not contain `safe to share`.
- Check generated bundle README contains privacy caution language.

## P2: `preserve_correlations` documentation omits `low`, but demo preset uses `low`

### Problem

`synth_spec()` docs describe `preserve_correlations` values as `none`, `moderate`, `high`, but `preset_table("demo")` uses `preserve_correlations = "low"`.

### Proposed fix

Choose one convention:

Option A: Use `none`, `moderate`, `high` only.

- Change demo preset from `low` to `none`.
- This is cleanest because `engine_from_correlations()` treats any value other than `moderate`/`high` as internal anyway.

Option B: Keep `low`.

- Document `low` as an accepted value.
- Consider validating `preserve_correlations` explicitly.

Prefer Option A unless the UI depends on displaying `low`.

### Tests to add

- `synth_spec("demo")$preserve_correlations` equals documented value.
- Validation catches unknown values if validation is added.

## P2: `name_strategy = "generic"` docs say `var1`, implementation uses `col_1`

### Problem

Roxygen says generic names are neutral names like `var1`, `var2`, but `apply_name_strategy()` creates `col_1`, `col_2`, etc.

### Proposed fix

Either:

- Update docs to say `col_1`, `col_2`, or
- Change implementation to `var1`, `var2`.

Prefer updating docs unless existing users/tests expect `col_1`.

### Tests to add

- `synth_spec(name_strategy = "generic")` followed by synthesis yields names matching the documented pattern.
- Data dictionary records original-to-synthetic mapping correctly.

## P2: Development objective engine routing is described inconsistently

### Problem

README engine section says lower-fidelity objectives use the dependency-free internal marginal engine, while analytics/high-fidelity uses synthpop. But `development` preset uses `preserve_correlations = "moderate"`, and `engine_from_correlations()` routes `moderate`/`high` to `synthpop` when available.

This may be intended, but then README should say development can use synthpop when installed. The code and print method already say relationship-aware synthesis uses synthpop when installed.

### Proposed fix

Update README engine section to match code:

- `demo`: internal marginal engine by default.
- `development`: auto-routes to synthpop when installed because it requests moderate relationship preservation; otherwise falls back to internal with warning.
- `analytics`: high-fidelity / synthpop path, with explicit risk acknowledgement.

Alternatively, if development should stay dependency-free by default, change its preset to `preserve_correlations = "none"` or explicit `engine = "internal"`.

### Tests to add

- With `options(dataganger.disable_synthpop = TRUE)`, development uses internal.
- If synthpop is unavailable, development falls back to internal with warning.
- If synthpop is available and not disabled, development uses synthpop only if this is intended.

## P2: Printed `engine_required` says `hifi`, but user-facing engines are `internal`, `marginal`, `synthpop`

### Problem

`engine_for()` returns `"hifi"` for `level == "hifi"` or `purpose == "analytics"`, and `print.dataganger_spec()` prints `Engine required: hifi`.

But valid engine names elsewhere are `internal`, `marginal`, `synthpop`. `hifi` is a synthesis level/fidelity concept, not an engine.

### Proposed fix

Rename or clarify:

Option A:

- Change field name to `fidelity_required` or `level_required` if it can be `hifi`.

Option B:

- Make `engine_required` return actual engine names, likely `synthpop` for hifi/analytics and `internal` otherwise.

Prefer Option B if this field is intended to describe engine routing.

### Tests to add

- `synth_spec("analytics", acknowledge_risk = TRUE)$engine_required` is a valid engine name, or docs say it is fidelity metadata.
- Printed spec output does not show `Engine required: hifi` unless explicitly documented.

## P2: Manifest privacy booleans are hard-coded and can become false claims

### Problem

`write_manifest()` hard-codes:

```r
raw_rows_included = FALSE
free_text_included = FALSE
ids_included = FALSE
plots_included = FALSE
```

But app roles support `simulation = "pass_through"`, and `apply_simulation_treatment()` copies original values into synthetic output for pass-through columns. Therefore, if an ID or free-text column is passed through, the manifest can falsely claim no IDs or free text were included.

### Proposed fix

Make manifest booleans computed from `roles`, `dictionary`, and/or output:

- Add `roles` parameter to `write_manifest()`.
- Compute `ids_included` from roles where direct identifiers or ID candidates remain in synthetic output and are not all missing.
- Compute `free_text_included` from roles where recommended role is free text and column remains non-missing or pass-through.
- Compute `raw_rows_included` if any `simulation == "pass_through"`.
- If uncertain, use `null` or `"unknown"` instead of hard-coded `FALSE`.

### Tests to add

- Bundle with pass-through ID column sets `ids_included = TRUE` or aborts if this is disallowed.
- Bundle with pass-through non-ID column sets `raw_rows_included = TRUE`.
- Default synthesized bundle keeps these fields false.

## P2: Dropped columns may be omitted from data dictionary and dropped-column report

### Problem

`build_data_dictionary()` builds rows from `name_map`, which defaults to names of the synthetic dataset. If a column is dropped before export, it may no longer be in synthetic names and may be absent from the dictionary. Then `build_dropped_variables_text()` only sees dictionary treatments and may report `None` even when columns were dropped.

### Proposed fix

Make dictionary construction aware of `original` and `roles`:

- Prefer iterating over original columns when `original` is supplied.
- Include dropped columns with `synthetic_variable = NA` or original name and treatment `dropped` / `masked_or_dropped`.
- Ensure `build_dropped_variables_text()` reports original variable names for dropped columns.
- If `include_original_names = FALSE`, still report neutral synthetic/dropped identifiers in a privacy-preserving way.

### Tests to add

- Original has a direct ID column that is dropped; dictionary includes that treatment.
- Bundle README `Columns dropped from the synthetic output` lists the dropped column or privacy-preserving equivalent.
- `dictionary_only` name strategy does not leak original names when `include_original_names = FALSE`.

## P3: `detect_roles()` roxygen mentions unsupported override input

### Problem

`detect_roles()` docs say assignments are overridable by passing a `user_role` column in a supplied roles tibble, but `detect_roles()` only accepts `data` and `profile`; there is no roles tibble parameter.

### Proposed fix

Remove or rewrite that sentence. Mention that overrides are applied by the Shiny Configure step and/or CLI role/spec files, not by passing roles into `detect_roles()`.

### Tests to add

None required beyond documentation build checks.

## P3: `privacy_check()` docs say roles are required for pre-stage flag detection, but implementation allows `roles = NULL`

### Problem

Docs say roles are required for pre-stage flag detection. Implementation can run without roles; it falls back to name/type heuristics.

### Proposed fix

Either:

- Enforce `roles` for `stage = "pre"`, or
- Update docs to say roles are recommended and used when supplied.

Prefer updating docs, because fallback behavior appears intentional.

### Tests to add

- `privacy_check(df, stage = "pre")` behavior remains documented.
- `privacy_check(df, roles = roles, stage = "pre")` uses disclosure roles.

## P3: Shiny step numbering mismatch

### Problem

Sidebar says:

1. Objective
2. Upload data
3. Configuration
4. Generation
5. Comparison
6. Export

But Generate header says `Step 05 · Generation`.

### Proposed fix

Change Generate header to `Step 04 · Generation`, or if another hidden step is intended, make sidebar and all headers follow the same numbering.

### Tests to add

Snapshot or grep-style test for consistent step labels if UI snapshots are already used.

## Suggested Codex task order

1. Fix P0 gate enforcement and tests.
2. Fix CLI analytics/engine YAML contract and tests.
3. Fix privacy overclaim wording in bundle README and AI README template.
4. Normalize role model documentation around `identifies`/`sensitive`.
5. Fix small doc/default mismatches: `low` vs `none`, `var1` vs `col_1`, `engine_required = hifi`.
6. Fix manifest booleans and dropped-column dictionary behavior.
7. Run:
   - `devtools::document()`
   - `devtools::test()`
   - `devtools::check()` or `rcmdcheck::rcmdcheck(args = c("--no-manual", "--as-cran"))`
   - `pkgdown::build_site()`

## Notes for implementation

- Prefer small helpers over duplicating checks across modules.
- Keep the two-axis role model as the source of truth: `identifies` + `sensitive`.
- Treat `disclosure_role` as compatibility metadata unless intentionally retaining it as public CLI contract.
- Avoid any wording that says synthetic data is guaranteed safe. Use “reduces direct disclosure risk” and “review before sharing externally.”
- Add regression tests before or with fixes, especially for the P0/P1 items.
