# AGENTS.md - dataganger verification contract

For any AI agent or human contributor working in this repository. These rules
exist because reviewed, locally-green branches have gone red on CI when the
local environment silently skipped tests (PR #39, 2026-07-10).

## Before every push (hard rules)

1. **Install missing Suggests instead of accepting skips.** A skipped test is
   an unverified test. If `devtools::test()` reports skips because a package
   (especially `synthpop`) is not installed, install it and re-run. "Package
   not installed" is never an acceptable reason to push unexecuted tests.
2. **Mirror the strictest CI job:**
   `DATAGANGER_TEST_SYNTHPOP=true Rscript -e 'devtools::test()'`
   must report 0 FAIL. Plain `devtools::test()` without synthpop installed is
   NOT equivalent - roughly 25 privacy-relevant tests skip silently.
3. **Audit the skip count.** With synthpop installed, expected residual skips
   are environment-bound only (chromote/CSS on headless boxes, `unshare` off
   Linux) - currently about 9. A jump in skips means silent coverage loss;
   explain it before claiming green.
4. **`devtools::check(manual = FALSE, vignettes = FALSE)`** must be 0 errors,
   0 warnings before push. CI runs with `error_on = "warning"`.
5. **ASCII only** in `R/`, `man/`, `DESCRIPTION`, `NAMESPACE`, and test files:
   no em-dashes, smart quotes, or arrows. Use `\uXXXX` escapes when a
   non-ASCII character is genuinely needed.
6. **Pin `engine = "internal"` in tests of engine-agnostic behavior.**
   `purpose = "development"` routes to synthpop when it is installed, so an
   unpinned spec makes a test's execution path depend on the local library.
   Leave the engine derived only in deliberately synthpop-specific tests.

## Privacy-critical surfaces - do not change without explicit owner approval

- The export bundle contract: `synthetic_data.csv` at root, `human/`
  (`human.md`, optional `comparison_report.html`), `agent/` (`recipe.yaml`,
  `AGENT.md`, `manifest.json`).
- The order of operations in `synthesize_data()`: `enforce_kanon()` runs
  BEFORE column renaming (`apply_name_strategy()`).
- The provable no-network guarantee: no external requests, CDN assets, or
  web fonts anywhere in package code or `inst/app/`.
- The privacy attestation gate and the Configure-page answer requirement
  (`roles_ready_for_generation()` on user-confirmed answers).
- Deterministic seeded synthesis: no unseeded randomness in synthesis paths.
- Enforcement outcomes must stay visible: warnings, the `kanon` attribute
  (including `suppressed_rows`/`suppressed_row_frac`, added 2026-07-21
  because whole-cell k-anon suppression can blank far more of a QI column
  than its cell count implies), and exact-row-match counts are carried
  through `run_synthesis_pipeline()` to the app UI (`mod-generate.R`
  `result_stats`, red "danger" styling when exact matches > 0), `human.md`
  (`render_kanon_line()`), `manifest.json`, and `dataganger inspect`
  (`cli_kanon_summary_line()`). Do not re-silence any of these, and keep all
  four surfaces in sync when one changes.
- "Alphanumeric ID" is the single catch-all for identifier-shaped columns
  (structural shape, name pattern, or high cardinality) as of 2026-07-21;
  there is no separate "pseudo identifier" type. Its default `simulation` is
  `"scramble"` (keep, de-identified), not `"drop"` -- a deliberate
  privacy-behavior decision, not a bug. `enforce_kanon()` exempts explicit
  `pass_through`/`scramble` decisions from the direct-identifier drop for
  the same reason.
- Character-stored dates/times (e.g. `"01/08/2020"`, a bare `"14:30"`) must
  get identical treatment to native `Date`/`POSIXct` columns: same
  `disclosure_role = "quasi"` default (set explicitly at both call sites in
  `detect_roles()` - `dg_suggest_disclosure()`'s class-keyed fallback only
  recognizes the literal R classes `"Date"`/`"POSIXct"`, not `"character"`),
  and synthesized through the same range/coarsen-aware machinery
  (`parse_date_like_character()` + `synth_date_like_character()` in
  `synth-helpers.R`) rather than falling through to generic categorical
  resampling. Format is preserved via round-trip-fidelity format detection,
  not just the first format string that happens to parse.
- Per-row role-mutation logic (type change, Q1/Q2 answer, action override)
  is centralized in `mod-roles.R`'s `apply_type_change()` /
  `apply_identifies_change()` / `apply_sensitive_change()` /
  `apply_simulation_change()`, shared by the single-column dropdowns and the
  bulk-configure toolbar. Extend those functions, not either caller
  individually, or the two editing paths will drift out of sync.

## Useful commands

```sh
# full verification loop (what CI effectively runs)
DATAGANGER_TEST_SYNTHPOP=true Rscript -e 'devtools::test()'
Rscript -e 'devtools::check(manual = FALSE, vignettes = FALSE)'

# run the app locally
Rscript -e 'dataganger::run_app()'
```

Project memory (decisions, TODO, handoffs) lives outside this repo in the
operator's memory system; this file carries only what a contributor needs to
verify changes correctly.
