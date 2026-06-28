# Documentation Refresh Plan — DataGangeR (2026-06-27)

Source: Plan agent survey. Brings all docs incl. pkgdown in sync with this
session's UX changes (A-D, F) plus the in-flight Configure redesign (E).

KEY DEPENDENCY: every doc item describing the per-column Configure UI must wait
until E lands in R/mod-roles.R. Split into phases accordingly.

## Already current (verified, no work)
- synth_spec.Rd documents all settings params (B).
- export_synthetic.Rd documents `compact` (D).
- detect_roles.Rd has no geography role (F).
- _pkgdown.yml: new helpers are @noRd internal -> nothing to export.
- inst/skills/using-dataganger-bundles/SKILL.md describes the FULL agent bundle
  (unchanged by D); optional one-line note about the compact app bundle.

## PHASE 1 (now; independent of E)
1. README.md: lead objective list with `development` + "(default)"; optionally
   soften step-3 caption. (low priority)
2. vignettes/articles/getting-started.Rmd:
   - "## 1. Objective": single Protection meter (Demo 5/Dev 3/Analytics 1),
     Development is DEFAULT, detail panel along consistent dimensions. (needs
     step-1 screenshot in Phase 2)
   - "## 6. Export": compact 6-file bundle; consolidated README (Privacy +
     "For AI assistants"); full CLI/agent bundle keeps standalone files.
   - "## 3. Configure": relabel role "None" -> "Measure / metric" (C). (settings
     table already matches B)
3. devtools::document() to keep man pages in sync (no manual .Rd edits).

## CLI PIPELINE (must be covered; Lennon flagged)
The end-to-end CLI/agent pipeline is core to the product story (human + AI use
the same spec). Audit and update:
- dataganger_cli help text / man page (man/dataganger_cli.Rd) and any CLI
  vignette/article: confirm flags match current synth_spec (no geography_*;
  current engine/name_strategy/etc.) and the disclosure-role values.
- README "Use it from R" + any CLI usage section: show the full reproduce-from-
  bundle pipeline (the same-seed analysis.qmd path) an agent runs; ensure it
  matches inst/templates/analysis_template.qmd and ai-readme.md.
- pkgdown: ensure dataganger_cli is in the reference index and an
  article/section walks the agent CLI workflow end to end.
- Cross-check the CLI bundle path (cli.R) still references existing files after
  the compact-bundle change (it reads the FULL bundle: manifest, dictionary,
  privacy_report.txt) - confirm docs describe FULL vs compact correctly.

## DOWNLOAD BUNDLE (must be covered; Lennon flagged)
Document the bundle contents in ONE authoritative place and reference it
everywhere consistently:
- App (compact) bundle: synthetic_data.csv, README.md (consolidated: Privacy +
  "For AI assistants"), load_data.R, analysis.qmd, data_dictionary.csv,
  manifest.json (+ comparison_report.html when included). ai-readme.md and
  privacy_report.txt are FOLDED INTO README.md.
- Full CLI/agent bundle (make_agent_bundle): keeps standalone ai-readme.md,
  privacy_report.txt, code_readiness_report.json, diagnostic_view.json, etc.
- Update: vignette "## 6. Export" (done in Phase 1 item 2), the in-bundle
  README generator wording if stale, inst/skills SKILL.md (note compact vs full),
  and any README/pkgdown mention of "what's in the download." Make the two
  bundle variants explicit so users/agents know which file to read.

## PHASE 2 (after E lands in mod-roles.R)
4. getting-started.Rmd "## 3. Configure": rewrite Per-column decisions to the
   4-option privacy-first dropdown + derived action + "what we'll do" + two-
   question help + k-anon auto-union. Source: dev/specs/2026-06-27-...-design.md.
5. README.md line ~56: "configure column disclosure roles" -> classify each
   column (who/what it identifies) + review what DataGangeR will do.
6. SCREENSHOTS LAST (chromote works on this WSL box; reuse driver pattern from
   commit 2465f40):
   - man/figures/hero.gif (full 6-step; new Objective + Configure)
   - vignettes/articles/step-1-objective.png (A)
   - vignettes/articles/step-3-configure.png + man/figures/step-3-configure.png (E)
   - vignettes/articles/step-6-export.png (D, if export panel changed)
   - VERIFY step-2-upload.png (per-column filter row, commit 41d92e0) and
     step-4-generate.png (recap now uses new labels); recapture if changed.
   - step-5-compare.png: unchanged.

## PHASE 3 (last)
7. NEWS.md: new top section covering A-E (+ data-preview filter row).
8. DESCRIPTION version: 0.3.6 if shipping A-D/F before E; 0.4.0 if E included.
   Run spelling::spell_check_package() (+ WORDLIST: k-anonymity, quasi-
   identifier, PII, PHI) and urlchecker before tagging.

Ordering: Phase 1 text -> document() -> WAIT for E -> Phase 2 text -> Phase 2
screenshots -> Phase 3 NEWS + version bump (final commit).
