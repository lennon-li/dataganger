# DataGangeR TODO: Lens-Oriented Improvements

This file captures the next improvements that would make DataGangeR useful as an agent-facing development-twin and diagnostic-bundle tool.

The goal is **not** to compete head-on with `synthpop` as a synthetic-data algorithm.

The stronger goal is:

> DataGangeR creates agent-ready development twins and diagnostic bundles without making the original data visible to the agent.

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

## Priority 2: Add agent-safe mode

Add a one-command workflow for creating an agent-ready bundle.

Example:

```bash
dataganger make-agent-bundle real_data.csv \
  --purpose ai_programming \
  --safe-mode strict \
  --out agent_bundle.zip
```

The bundle should include:

```text
synthetic_data.csv
data_dictionary.csv
ai-readme.md
diagnostic_view.json
privacy_report.txt
manifest.json
load_data.R
```

### Principle

The agent should receive the bundle, not the original dataset.

If an agent calls DataGangeR directly against real data, that call should happen only inside a trusted environment or a Lens-controlled runner.

## Priority 3: Integrate `synthpop` as a backend

DataGangeR should treat `synthpop` as a synthesis backend, not as a competitor.

Target API:

```r
synthesize_data(data, spec, engine = "internal")
synthesize_data(data, spec, engine = "synthpop")
```

### Design position

- DataGangeR handles workflow, roles, purpose presets, privacy warnings, export bundles, and UI.
- `synthpop` can handle stronger statistical synthesis when requested.
- Internal engine remains useful for fast schema-only and marginal development twins.

### Acceptance criteria

- `engine = "synthpop"` no longer aborts when `synthpop` is installed.
- Clear fallback message when `synthpop` is not installed.
- Comparison reports work for both internal and `synthpop` engines.
- Privacy checks run after either engine.

## Priority 4: Export a Lens-compatible Diagnostic Package

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
      "sensitive": false
    }
  ],
  "blocked": {
    "raw_rows": true,
    "free_text": true,
    "ids": true
  }
}
```

### Acceptance criteria

- Diagnostic package contains approved structure only.
- Raw rows are never included.
- Free-text examples are never included.
- IDs are dropped, masked, or represented only as blocked fields.
- Numeric ranges and factor levels are configurable by policy.

## Priority 5: Accept a policy / pDUA file

DataGangeR should accept a machine-readable policy file that determines what can be preserved, coarsened, renamed, or exported.

Example:

```yaml
purpose: ai_programming
allow_original_names: true
allow_factor_levels: false
allow_numeric_ranges: false
min_cell_n: 5
drop_free_text: true
drop_ids: true
coarsen_dates: month
```

Possible CLI:

```bash
dataganger make-agent-bundle real.csv --policy policy.yaml --out agent_bundle.zip
```

### Terminology

- Formal privacy/governance name: Programmatic Data Use Agreement, or pDUA.
- Developer-friendly name: policy file.

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

## Priority 7: Add dry-run commands for agents

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

## Priority 8: Strengthen privacy wording without overclaiming

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

## Priority 9: Align DataGangeR with Lens boundaries

Recommended division of responsibilities:

```text
DataGangeR
  - reads real data inside trusted environment
  - profiles data
  - detects roles
  - creates synthetic twin
  - exports agent-ready bundle
  - exports diagnostic package

Lens
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
4. Policy/pDUA input.
5. `synthpop` backend.
6. Code-readiness checks.
7. Agent dry-run helper commands.

## Explicit non-goals for now

- Do not build a full Lens runner inside DataGangeR.
- Do not claim formal privacy guarantees.
- Do not try to replace `synthpop`.
- Do not make Shiny the primary agent workflow.
- Do not require cloud LLM APIs.
