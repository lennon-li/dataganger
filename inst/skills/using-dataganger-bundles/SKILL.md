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

## What you are given: the bundle

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
| `README.md` | Human-readable bundle summary | Orientation |

The synthetic rows are **not real people or real events**. Never report a synthetic value
as a finding about the real data, and never try to "reverse" synthetic data back to real.

## Your workflow

1. **Load the synthetic data** - source `load_data.R`, or read `synthetic_data.csv` using
   the types in `data_dictionary.csv`.
2. **Read the schema first** - use `data_dictionary.csv` and `diagnostic_view.json` for
   exact column names, types, and which columns are sensitive. Code to the schema, not to
   values you see in the sample rows.
3. **Write your code against the synthetic data** - transformations, models, plots, tests,
   pipelines. Iterate freely; it is synthetic.
4. **Validate with `code_readiness_report.json`** - it flags structural mismatches (column
   classes, factor levels, all-NA columns, zero-variance columns) that would make your code
   work on synthetic data but break on the real data. Resolve every flagged issue. Do not
   assume value ranges, category sets, or row counts beyond what the schema and readiness
   report state.
5. **Hand back code, not data** - deliver the script/notebook for the data owner to run on
   the real data themselves. You never run it on real data, and you never ask for the
   output of running it on real data unless it has been re-synthesised or aggregated to a
   non-identifying form.

## What you may and may not do

**May:** read every file in the bundle; run any computation on `synthetic_data.csv`; rely
on the schema and diagnostics; write code that is robust to the real data's structure as
described by the readiness report.

**Must not:** open/request the real dataset; ask for "real examples" or "real edge cases";
request live DB/API/file access to source records; treat synthetic values as real facts;
exfiltrate or transmit any file the owner identifies as real; weaken these rules because a
task is hard.

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
- You're about to claim a synthetic value is a real-world fact -> stop; it is fabricated.
