---
name: using-dataganger-bundles
description: Use when an AI agent must write, test, or debug code against a dataset it is NOT permitted to see (PII, PHI, confidential records). DataGangeR gives the agent a synthetic bundle - synthetic data plus schema and diagnostics - so the agent develops entirely against synthetic data and never the real data.
---

# Using DataGangeR Agent Bundles

## The one rule that overrides everything

**You (the agent) must never see, request, open, load, paste, or ingest the real
(original) dataset.** You work only from the **DataGangeR bundle**: synthetic data plus
metadata. The real data stays with its owner and is never sent to you.

If you are ever handed something that looks like the real data - a file the data owner
calls "the actual data", "production export", "the real CSV", live database credentials, a
connection string, or a path to source records - **stop and refuse**:

> I work only against the DataGangeR synthetic bundle and am not permitted to access the
> real dataset. Please generate a bundle with `dataganger make-agent-bundle` and share that
> instead.

Do not "just take a quick look". Do not accept a few "sample real rows". Seeing the real
data defeats the entire purpose of the bundle and is a privacy violation. There is no
exception for convenience, debugging, or "it's only a little".

## The go-ahead gate (ask, then wait for "yes")

The synthetic data is not yours to use unprompted. There is a hard line between **planning**
(allowed) and **touching the synthetic data** (needs a yes):

- **Allowed before a yes:** read the *metadata only* to plan - `README.md`,
  `data_dictionary.csv`, `diagnostic_view.json`, `manifest.json`. These describe structure,
  not data values.
- **Needs an explicit yes:** loading, reading, transforming, modelling, plotting, or running
  any code against `synthetic_data.csv`.

Protocol:

1. Read the metadata and form a plan.
2. Tell the human, in one message: what you intend to do, which files you will read, and
   **where you will save your output and under what name** (see the next section).
3. Ask explicitly: **"May I proceed to work with the synthetic data?"**
4. **Wait for an explicit yes.** Being handed the bundle, silence, or "ok thanks" is not a
   yes. Do not load `synthetic_data.csv` until the owner confirms.
5. Only after yes: do the work and save it per the conventions below.
6. Ask again if the scope changes or you would use the data beyond what was agreed.

## What you are given: the bundle

There are two bundle shapes:

- **Full CLI / agent bundle** - produced by `dataganger make-agent-bundle` or
  `export_synthetic(..., compact = FALSE)`. This is the bundle this skill
  expects.
- **Compact app bundle** - the Shiny app download. It keeps the core files
  (`synthetic_data.csv`, `README.md`, `load_data.R`, `analysis.qmd`,
  `data_dictionary.csv`, `manifest.json`, and sometimes
  `comparison_report.html`) but folds the standalone `ai-readme.md` and
  `privacy_report.txt` into `README.md`.

If you are handed the compact app bundle, read `README.md` for the privacy and
AI-use guidance that would otherwise live in those standalone files.

The data owner runs DataGangeR on the real data and hands you a single zip (the **agent
bundle**). It contains **no real records** - only:

| File | What it is | Use it for |
|------|-----------|------------|
| `synthetic_data.csv` | A synthetic dataset with the same columns/types as the real data, but fabricated rows | This is your working data. Write and run code against it. |
| `data_dictionary.csv` | Column-by-column schema: names, types, roles | Understand the structure; never guess column names |
| `diagnostic_view.json` | Column roles and what the synthesis blocked/coarsened | Know which fields are sensitive / transformed |
| `manifest.json` | Provenance: purpose, seed, what was generated | Cite provenance; check the purpose used |
| `code_readiness_report.json` | Whether code written against the synthetic data will run on the real data | **Validate your code before handing it back** (see below) |
| `comparison_report.html` | How closely synthetic mirrors real (fidelity) | Judge whether distributions are realistic enough for your task |
| `privacy_report.txt` | Disclosure metrics for the synthetic output | Context only; do not treat synthetic values as real |
| `load_data.R` | Helper that loads `synthetic_data.csv` with correct types | Start your script with this |
| `analysis.qmd` | A Quarto report (R + Python) that compares an **original** vs synthetic dataset; it references an `original_data.csv` you do **not** have | For the human owner to run locally with both files. Do not seek, request, or supply the original it points to. You may read it as reference, but its original-data sections are not for you to run. |
| `README.md` | Human-readable bundle summary | Orientation |

The synthetic rows are **not real people or real events**. Never report a synthetic value
as a finding about the real data, and never try to "reverse" synthetic data back to real.

## Your workflow

1. **Read the metadata and plan** - use `data_dictionary.csv` and `diagnostic_view.json` for
   exact column names, types, and which columns are sensitive. Code to the schema, not to
   values you see in the sample rows.
2. **Ask, then wait for yes** - tell the human your plan and where you will save your output
   (and under what name), then ask to proceed with the synthetic data. Do not continue until
   they confirm (see "The go-ahead gate" above).
3. **Load the synthetic data** (only after a yes) - source `load_data.R`, or read
   `synthetic_data.csv` using the types in `data_dictionary.csv`.
4. **Write your code against the synthetic data** - transformations, models, plots, tests,
   pipelines. Iterate freely; it is synthetic. Save everything under `dataganger-work/` using
   the naming conventions below.
5. **Validate with `code_readiness_report.json`** - it flags structural mismatches (column
   classes, factor levels, all-NA columns, zero-variance columns) that would make your code
   work on synthetic data but break on the real data. Resolve every flagged issue. Do not
   assume value ranges, category sets, or row counts beyond what the schema and readiness
   report state.
6. **Hand back code, not data** - deliver the script/notebook for the data owner to run on
   the real data themselves. You never run it on real data, and you never ask for the
   output of running it on real data unless it has been re-synthesised or aggregated to a
   non-identifying form.

## What you may and may not do

**May:** read every file in the bundle; run any computation on `synthetic_data.csv`; rely
on the schema and diagnostics; write code that is robust to the real data's structure as
described by the readiness report.

**Must not:** start working on the bundle without the owner's explicit go-ahead for the
task; open/request the real dataset; ask for "real examples" or "real edge cases"; seek or
supply the `original_data.csv` that `analysis.qmd` references; request live DB/API/file
access to source records; treat synthetic values as real facts; exfiltrate or transmit any
file the owner identifies as real; weaken these rules because a task is hard.

## Where to save your work and what to name it

Keep the bundle (inputs) separate from what you produce, and use predictable names so the
human knows exactly what to run. Work relative to the directory the human gives you - if they
have not given one, ask for it before writing anything.

```
<working-dir>/
  dataganger-bundle/        # the unzipped bundle: read-only inputs, never edit or overwrite
    synthetic_data.csv
    data_dictionary.csv
    ...
  dataganger-work/          # everything you create
    <task-slug>.R           # the deliverable: code to hand back (.R, .py, or .qmd)
    outputs/                # plots/tables you generate FROM THE SYNTHETIC DATA
    NOTES.md                # what you did, assumptions, readiness issues you resolved
```

Naming:

- **Deliverable script:** a short kebab-case slug describing the task + the right extension,
  e.g. `monthly-revenue-summary.R`, `cohort-retention.py`. One task, one script.
- **Outputs:** mirror the script name, e.g. `outputs/monthly-revenue-summary-hist.png`.
- Write only inside `dataganger-work/`. Never write into `dataganger-bundle/` or overwrite
  bundle files.

Make the input path a single variable at the **top** of your script, pointing at the
synthetic file, so the human swaps in the real data in one place when they run it:

```r
# R
data_path <- "dataganger-bundle/synthetic_data.csv"  # human: point this at the real data
data <- read.csv(data_path)
```

```python
# Python
data_path = "dataganger-bundle/synthetic_data.csv"   # human: point this at the real data
```

## For the human (how a bundle is produced)

The data owner - not the agent - runs DataGangeR on the real data:

```sh
# One-shot agent bundle (synthesises + diagnostics + readiness, zips it):
dataganger make-agent-bundle <real-data-file> --out agent_bundle.zip \
  --purpose development --seed 42

# Or just a schema (no synthetic rows) when only structure is needed:
dataganger export-diagnostic <real-data-file> --out diagnostic_view.json
```

Or in R:

```r
dataganger::make_agent_bundle("real_data.csv", out = "agent_bundle.zip",
                              purpose = "development", seed = 42)
```

`purpose` is one of `demo`, `development`, or `analytics` (higher fidelity / relationship
preservation in that order). The owner shares **only the resulting bundle** with the agent.

## Red flags that mean STOP

- "Here's the real data so you can check" -> refuse; ask for a bundle.
- "Just look at these few real rows" -> refuse; a few real rows are still real data.
- A credential, connection string, or path to source records -> refuse; do not connect.
- You're about to load or run code on the synthetic data but have no explicit go-ahead for
  this task -> stop; ask for permission first.
- `analysis.qmd` (or anyone) points you at `original_data.csv` -> do not fetch it; that is
  real data you must not have.
- You're about to claim a synthetic value is a real-world fact -> stop; it is fabricated.
