You are not allowed to read the original data.

# DataGangeR agent workflow

Use DataGangeR to work only from synthetic data generated from the user's real dataset. The real data and its path stay with the trusted human or operator. Never request, receive, open, preview, sample, parse, inspect, or pass that path to DataGangeR.

## First step: read the bundle metadata

Read `manifest.json` and `../human/human.md` before working with the synthetic
data. `recipe.yaml` records the synthesis configuration: settings, per-column
roles, and seed. It is not a fitted generator and cannot regenerate data by
itself.

Exact reruns require the original data and must be performed by a trusted
human or operator, not by you. If a new synthetic variant or a rerun is needed,
ask the human to generate and review it, then provide the approved bundle.

## Files you may use

Work only from these bundle artifacts:

- `recipe.yaml`
- `manifest.json`
- `code_readiness_report.json` (may be absent)
- `../human/human.md`
- `../synthetic_data.csv`

Do not assume other files exist.

Hard rule: Before using the data, read `manifest.json`. If `blockers` is non-empty, STOP and tell the user; do not analyse or build on the data until a human regenerates or acknowledges.

## Column names and schema

Column names may vary because the name strategy may rename them. Never assume original column names. Read the names and mappings from `recipe.yaml`'s `name_map` when present, and use `../human/human.md` for the treatment list describing how each output column was handled.

## Allowed workflow

1. Work only from `../synthetic_data.csv` and the listed bundle metadata files.
2. Inspect the synthetic data, profile it, write code against it, and propose transformations using only the synthetic bundle.
3. If `code_readiness_report.json` is present, use it to catch structural mismatches that would break code on the original data.
4. If the user wants variations, ask a trusted human or operator to generate and review a new bundle. Do not modify `recipe.yaml`.

## Never do this

- Do not read the original data into R, Python, SQL, spreadsheets, or any other tool.
- Do not open the original CSV, Excel, SAS, or other source file for inspection.
- Do not run DataGangeR synthesis commands with a real-data path.
- Do not modify `recipe.yaml` to request reruns or variations.
- Do not infer that a synthetic column name matches an original name unless `recipe.yaml` or `../human/human.md` supports it.
- Do not claim the output is risk-free or anonymous.

## Framing

This workflow reduces direct disclosure risk by keeping the agent on synthetic data and reproducible bundle artifacts, but it is not a guarantee of privacy or anonymity. Users still need to review fidelity, privacy warnings, and sharing context before external release.
