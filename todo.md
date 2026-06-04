# DataGangeR TODO: Lens-Oriented Improvements

This file captures the next improvements that would make DataGangeR useful as an agent-facing development-twin and diagnostic-bundle tool.

## Strategic decision after Lens synthesis review

The Lens synthesis review makes one thing clear: **Lens should not be built as a full platform first.** The strongest path is:

> Build DataGangeR first as the concrete agent-ready bundle generator, then let Lens specify and govern what those bundles mean.

DataGangeR should become the first practical implementation component of Lens, not a side project.

The goal is **not** to compete head-on with `synthpop` as a synthetic-data algorithm.

The stronger goal is:

> DataGangeR creates agent-ready development twins and diagnostic bundles without making the original data visible to the agent.

## v0.3 target

DataGangeR v0.3 should deliver one credible object:

```text
agent_bundle.zip
```

The bundle should be safe enough for an analyst to hand to an AI agent for code prototyping, while still being honest that it is not a formal privacy guarantee.

Minimum bundle contents:

```text
synthetic_data.csv
data_dictionary.csv
ai-readme.md
diagnostic_view.json
privacy_report.txt
manifest.json
load_data.R
```

## Priority 1: Add a real CLI workflow

DataGangeR should support terminal commands, not only R-console and Shiny workflows.

Agents can call CLI tools more reliably than they can operate an interactive Shiny app.

Possible commands:

```bash
dataganger profile real_data.sas7bdat --out profile.json
dataganger roles real_data.sas7bdat --out roles.yaml
dataganger spec --purpose ai_programming --out spec.yaml
dataganger synthesize real_data.sas7bdat --spec spec.yaml --out synthetic_bundle.zip
dataganger inspect synthetic_bundle.zip
```

### Acceptance criteria

- CLI can run the core package workflow without opening Shiny.
- CLI supports CSV, Excel, SAS, and XPT inputs through existing `read_input()` logic.
- CLI returns machine-readable output where appropriate: JSON/YAML/CSV.
- CLI exits with useful status codes for automation.
- CLI never sends data to an LLM or cloud API.

## Priority 2: Add `make-agent-bundle`

Add a one-command workflow for creating an agent-ready bundle.

Example:

```bash
dataganger make-agent-bundle real_data.csv \
  --purpose ai_programming \
  --safe-mode strict \
  --out agent_bundle.zip
```

### Principle

The agent should receive the bundle, not the original dataset.

If an agent calls DataGangeR directly against real data, that call should happen only inside a trusted environment or a future Lens-controlled runner.

### Acceptance criteria

- Uses existing `read_input()`, `profile_data()`, `detect_roles()`, `synth_spec()`, `synthesize_data()`, `compare_synthetic()`, `privacy_check()`, and `export_synthetic()` where possible.
- Produces a complete `agent_bundle.zip`.
- Fails closed when privacy flags are high unless the user explicitly overrides.
- Writes a clear `ai-readme.md` explaining what the agent may and may not assume.

## Priority 3: Export a Lens-compatible Diagnostic Package

Add a formal export for agent/Lens workflows.

Possible R function:

```r
export_diagnostic_package(data, roles, profile, spec, path)
```

Possible CLI:

```bash
dataganger export-diagnostic real_data.csv --out diagnostic_view.json
```

Example output:

```json
{
  "dataset": {
    "n_rows_bucket": "10000-50000",
    "n_cols": 24
  },
  "columns": [
    {
      "name": "age_group",
      "type": "factor",
      "role": "categorical candidate",
      "sensitive": false,
      "exposed": true,
      "exposure_level": "schema_only"
    }
  ],
  "blocked": {
    "raw_rows": true,
    "free_text_examples": true,
    "ids": true,
    "plots": true
  }
}
```

### Acceptance criteria

- Diagnostic package contains approved structure only.
- Raw rows are never included.
- Free-text examples are never included.
- IDs are dropped, masked, or represented only as blocked fields.
- Numeric ranges and factor levels are configurable by policy.
- Row counts are bucketed or suppressed according to policy.
- Output is stable JSON that Lens can later ingest.

## Priority 4: Add manifest fields for Lens exposure logging

The export bundle should include a `manifest.json` that can later seed a Lens Exposure Ledger.

Example fields:

```json
{
  "source": "dataganger",
  "package_version": "0.3.0",
  "purpose": "ai_programming",
  "created_at": "2026-06-01T00:00:00Z",
  "original_rows_bucket": "10000-50000",
  "original_columns_count": 24,
  "raw_rows_included": false,
  "free_text_included": false,
  "ids_included": false,
  "plots_included": false,
  "original_names_included": true,
  "factor_levels_included": false,
  "numeric_ranges_included": false,
  "policy_file": "policy.yaml"
}
```

### Acceptance criteria

- Manifest records exactly what structural information was included.
- Manifest records what was intentionally blocked.
- Manifest does not include raw records.
- Manifest is suitable for later Lens audit/evidence reporting.

## Priority 5: Accept a policy file / pDUA-lite

DataGangeR should accept a machine-readable policy file that determines what can be preserved, coarsened, renamed, or exported.

Use simple language in the developer interface:

> policy file

Use institutional language only in documentation:

> Programmatic Data Use Agreement, or pDUA

Example:

```yaml
purpose: ai_programming
allow_original_names: true
allow_factor_levels: false
allow_numeric_ranges: false
row_count_strategy: bucket
min_cell_n: 5
drop_free_text: true
drop_ids: true
coarsen_dates: month
block_plots: true
```

Possible CLI:

```bash
dataganger make-agent-bundle real.csv --policy policy.yaml --out agent_bundle.zip
```

### Acceptance criteria

- Policy can override purpose presets.
- Policy is written back into the bundle or referenced in the manifest.
- Unsafe combinations trigger warnings or hard stops.
- Documentation avoids claiming legal compliance.

## Priority 6: Add code-readiness checks

DataGangeR should measure whether the synthetic development twin is useful for coding, not only whether it resembles the original statistically.

Possible function:

```r
check_code_readiness(original, synthetic, roles = NULL)
```

Checks should include:

- same column names or documented name mapping;
- compatible R classes;
- compatible factor/label structures where allowed;
- date compatibility;
- missingness compatibility;
- join-key compatibility;
- no all-NA columns unless intentional;
- model-formula compatibility;
- common tidyverse pipeline compatibility.

### Key metric

> Will code written on the synthetic data run on the real data?

This is a major distinction from general-purpose synthetic-data packages.

### Acceptance criteria

- Returns a structured report, not just printed text.
- Identifies likely causes of downstream code failure.
- Can be included in the agent bundle.
- Distinguishes statistical utility from code utility.

## Priority 7: Integrate `synthpop` as a backend

DataGangeR should treat `synthpop` as a synthesis backend, not as a competitor.

Target API:

```r
synthesize_data(data, spec, engine = "marginal")
synthesize_data(data, spec, engine = "synthpop")
```

UI wording:

```text
Built-in fast engine (marginal)
synthpop engine (model-based)
```

Avoid describing the built-in engine as "random number generation." It should be described as DataGangeR's built-in marginal synthesis engine: fast, simple, and useful for development twins.

### Design position

- DataGangeR handles workflow, roles, purpose presets, privacy warnings, export bundles, Shiny UI, CLI, and agent-readiness.
- `synthpop` can handle stronger statistical synthesis when requested.
- Internal engine remains useful for fast schema-only and marginal development twins.

### Required review before implementation

Before implementing `synthpop` behind the UI, run a focused technical design review.

Do **not** ask for a broad synthetic-data literature review. The review should translate `synthpop` into DataGangeR design decisions.

Review task:

```markdown
# Review task: DataGangeR synthpop integration

Goal: determine how DataGangeR should wrap `synthpop` as an optional synthesis engine behind the UI and CLI.

Please answer:

1. What does `synthpop::syn()` actually do?
   - synthesis order
   - default methods
   - predictor matrix
   - treatment of categorical, numeric, date, labelled, missing, and high-cardinality variables

2. Which `synthpop` options matter for DataGangeR?
   - which should be hidden
   - which should be exposed under Advanced
   - which should be controlled by DataGangeR purpose presets

3. How should DataGangeR map purposes to synthpop settings?
   - ai_programming
   - shiny_prototype
   - teaching
   - model_prototype
   - internal_hifi
   - safer_external

4. What preprocessing should DataGangeR do before calling synthpop?
   - remove IDs
   - drop or redact free text
   - coarsen dates
   - merge rare levels
   - handle labelled SAS variables
   - handle geography

5. What postprocessing should DataGangeR do after synthpop?
   - privacy_check()
   - compare_synthetic()
   - exact-row match check
   - rare-level survival check
   - code-readiness check
   - export agent bundle

6. What UI wording should be used?
   - built-in fast engine
   - synthpop engine
   - warnings and explanations

7. What should DataGangeR not claim?
   - no privacy guarantee
   - no legal compliance claim
   - no claim that synthpop output is automatically safe for external sharing

8. Licensing/dependency implications
   - synthpop is GPL-2/GPL-3
   - DataGangeR is currently MIT
   - should synthpop stay in Suggests?
   - should engine='synthpop' require optional installation?
```

### Initial implementation stance

Keep `synthpop` optional.

Recommended pattern:

```r
if (!requireNamespace("synthpop", quietly = TRUE)) {
  cli::cli_abort("Install {.pkg synthpop} to use engine = 'synthpop'.")
}

syn_obj <- synthpop::syn(data, ...)
synthetic <- syn_obj$syn
```

Do not move `synthpop` from `Suggests` to `Imports` until dependency and licensing implications are reviewed.

### UI placement

Put the engine selector under an Advanced section first:

```text
Advanced
  Synthesis engine:
    ○ Built-in fast engine (marginal)
    ○ synthpop engine (model-based)
```

Suggested help text:

```text
Built-in fast engine
Uses DataGangeR's built-in marginal synthesis. Best for AI programming,
Shiny prototypes, teaching, and quick development twins.

synthpop engine
Uses model-based synthesis from the synthpop package. Better for preserving
relationships between variables, but slower and requires more review before sharing.
```

### Acceptance criteria

- `engine = "synthpop"` no longer aborts when `synthpop` is installed.
- Clear fallback message when `synthpop` is not installed.
- Comparison reports work for both built-in marginal and `synthpop` engines.
- Privacy checks run after either engine.
- Documentation states when the built-in marginal engine is preferred and when `synthpop` is preferred.
- Shiny UI exposes engine choice under Advanced, not as the main decision.
- CLI supports engine choice with a clear default.

## Priority 8: Add dry-run commands for agents

Agents should be able to inspect a synthetic bundle without touching original data.

Possible commands:

```bash
dataganger describe-bundle agent_bundle.zip
dataganger print-schema agent_bundle.zip
dataganger suggest-r-template agent_bundle.zip
```

### Acceptance criteria

- Commands operate only on exported bundles.
- Commands never require the original data path.
- Outputs are concise enough to paste into an agent context window.
- Outputs do not reveal more than the manifest/policy allows.

## Priority 9: Strengthen privacy wording without overclaiming

Keep the current honest posture.

Do not say:

> safe synthetic data

Prefer:

> reviewable synthetic development double

or:

> agent-ready development twin with disclosure-risk warnings

### Documentation rule

DataGangeR should always state:

- synthetic output reduces direct disclosure risk;
- it does not guarantee privacy;
- sharing decisions require context-specific review;
- legal compliance is not provided by the package alone.

## Priority 10: Align DataGangeR with Lens boundaries

Recommended division of responsibilities:

```text
DataGangeR
  - reads real data inside trusted environment
  - profiles data
  - detects roles
  - creates synthetic twin
  - exports agent-ready bundle
  - exports diagnostic package
  - exports manifest for Lens audit/evidence layer

Lens
  - specifies diagnostic package standards
  - controls what the agent receives
  - runs code safely
  - sanitizes feedback
  - logs exposure
  - evaluates leakage
```

DataGangeR should feed Lens, not become Lens.

## Near-term implementation order

1. CLI wrapper around existing functions.
2. `make-agent-bundle` command using existing export machinery.
3. Diagnostic package export.
4. Manifest fields for Lens exposure logging.
5. Policy file / pDUA-lite input.
6. Code-readiness checks.
7. Focused `synthpop` integration review.
8. `synthpop` backend.
9. Agent dry-run helper commands.

## Explicit non-goals for now

- Do not build a full Lens runner inside DataGangeR.
- Do not claim formal privacy guarantees.
- Do not try to replace `synthpop`.
- Do not make Shiny the primary agent workflow.
- Do not require cloud LLM APIs.
- Do not implement MCP yet.
- Do not build an agent-to-LLM interface inside DataGangeR.

## Relationship to Lens v0.1

Lens should remain mostly a specification and evaluation repo until DataGangeR can generate `agent_bundle.zip` reliably.

Suggested Lens-side specs later:

```text
docs/specs/diagnostic-package-v0.md
docs/specs/exposure-ledger-v0.md
docs/specs/sanitized-feedback-v0.md
docs/specs/runner-threat-model-v0.md
```

Do not start Lens runner implementation until DataGangeR has a stable agent bundle format.
