# Disclosure roles + k-anonymous synthetic output — Design

Date: 2026-06-21
Status: Approved for planning
Branch context: `main`

## Problem

Today the only disclosure control a user can express is a single per-column
`sensitive` boolean (`R/detect-roles.R`). Downstream it does almost nothing —
`privacy_check_pre()` raises a "review whether to coarsen or exclude" flag, so
in practice the only lever a user feels is **keep vs. drop**. Two real risks are
not captured at all:

1. **Quasi-identifier combinations.** A column can be harmless alone yet
   identifying in combination with others (the classic `{ZIP, birth_date, sex}`
   re-identifies ~87% of the US population). There is no notion of a
   quasi-identifier set as user input, and no combination-level check — the
   existing checks are single-column only.
2. **Small cells.** A combination held by fewer than ~5 people is
   re-identifiable. There is no combination cell-size (k-anonymity) check on
   either the original or the synthetic output.

## Goals

- Let users declare each column's **disclosure role** with plain-language
  definitions.
- Make the **released synthetic dataset provably k-anonymous** (default k = 5)
  over the declared quasi-identifiers, with direct identifiers removed.
- Surface a verifiable, reviewer-facing readout of the guarantee.

## Non-goals (v1, explicitly out of scope)

- **Attribute disclosure / l-diversity** — protecting *Sensitive* targets beyond
  the QI guarantee. The role is captured but not yet enforced.
- **Continuous-outlier disclosure** (e.g. a synthetic income matching a real
  outlier).
- **Aggregate / tabular inputs.** Policy assumes individual-level microdata; an
  aggregate-looking input is detected and warned about, not handled with a
  separate small-cell-suppression engine.

## Core guarantee

> Policy applies to **individual-level microdata only**. The promise dataganger
> makes: the released synthetic dataset is **k-anonymous (default k = 5)** over
> the user-declared quasi-identifier columns; direct identifiers are removed.

This is a checkable property of the released artifact, not a process to trust.
The original's small cells are irrelevant once they cannot survive into the
output.

### Why aggregate vs. individual-level matters

The unit of observation decides which policy applies:

- **Individual-level microdata** (one row = one person): the "cell" is the
  *equivalence class* of records sharing a quasi-identifier combination. A
  combination held by < k people means those people are re-identifiable. Remedy:
  generalize/suppress the quasi-identifiers so no such combination survives into
  the output. This is what we build.
- **Aggregate / tabular data** (one row = a group statistic): the classic
  small-cell-suppression rule applies to the table's own count cells. The row is
  not a person; QIs and generalization do not transfer. Out of scope — detect
  and warn only.

The arithmetic (count per combination < k) looks the same in both, but the
*meaning* (re-identification vs. aggregate disclosure) and *remedy*
(pre-output generalization vs. output cell suppression) differ.

## Disclosure-role definitions (user-facing)

These strings appear verbatim in the DISCLOSURE column tooltip and the package
help.

| Role | What it means | What dataganger does | Examples |
|---|---|---|---|
| **None** *(not identifying)* | A value that can't point to a specific person — alone or in combination. Usually a measurement many people share. | Synthesized normally. Ignored by the k-anonymity check. | lab result, blood pressure, a survey score, generic numeric reading |
| **Direct identifier** | Singles out one person **by itself** — no combination needed. | **Removed / masked** — never appears in the synthetic output. | name, MRN, SSN/SIN, email, phone, exact address, `patient_id` |
| **Quasi-identifier** | Harmless alone, but **in combination** with other quasi-identifiers can single someone out by matching against outside knowledge. | Kept, but the synthetic output is forced **k-anonymous** over all quasi-identifiers together; coarsened/suppressed as needed. | date of birth, ZIP/postal code, sex, age, ethnicity, admission date |
| **Sensitive** *(target)* | Private information you keep **for analysis** but don't want linked back to a person — what an attacker would *learn* if they re-identified someone. | Kept for analysis. **v1: no extra protection beyond the QI guarantee** (l-diversity planned). | diagnosis, income, HIV status, test result, salary |

**The distinction users always trip on** (shown as a one-line note under the
selector):

> **Quasi-identifier = how someone could be *found*** (linkable to external
> data). **Sensitive = what you don't want *revealed*** about them once found.
> If a column is both linkable *and* private (e.g. a rare diagnosis), mark it
> **Quasi-identifier** — that's what puts it under the k guarantee.

## Data model

- `dataganger_roles`: replace the `sensitive` logical with:
  - `disclosure_role` — one of `"none"`, `"direct"`, `"quasi"`, `"sensitive"`.
  - `disclosure_reason` — short justification for the auto-assignment.
- Migrate existing `sensitive` consumers (`privacy-check.R`,
  `export-diagnostic.R`, `make-agent-bundle.R`, `mod-*`) onto `disclosure_role`.
  Do **not** keep both fields.
- Spec (`dataganger_spec`): add `k_anon` (integer, default `5`).
- QI set is derived: `roles$variable[disclosure_role == "quasi"]`. Direct
  identifiers are `disclosure_role == "direct"`.

### Auto-fill mapping (`detect_roles`)

- ID-pattern / `n_distinct/nrow >= 0.95` / high-uniqueness free-text / name
  pattern → `direct`.
- geography / date / low-cardinality categorical → `quasi`.
- numeric measurements and everything else → `none`.
- `sensitive` is **never** auto-assigned (too unreliable); the user promotes a
  column to it deliberately.

## Capture UX (Configuration page, `mod-roles.R`)

- The roles table gains a **DISCLOSURE** column: a per-row dropdown
  (None / Direct identifier / Quasi-identifier / Sensitive), pre-filled from the
  auto-fill mapping, colour-cued like the existing TYPE tint.
- A single **Minimum cell size (k)** numeric input (default 5) with a one-line
  explainer, beside the table.
- The definitions table above is reachable via an info popover on the DISCLOSURE
  column header; the Quasi-vs-Sensitive note sits under the selector.

## Aggregate detect-and-warn (new, light)

- `looks_aggregated(data)` heuristic: presence of a count-like column
  (`n`, `count`, `freq`, or a non-negative integer column that plausibly sums to
  a population) **and** low row count **and** group-by structure (repeated
  dimension combinations). Returns a boolean + reason.
- On a positive result, show a one-line, non-blocking warning on Upload /
  Configuration: "Disclosure control assumes individual-level data; aggregate
  small-cell rules aren't applied." No aggregate policy engine is built.

## Risk computation

New pure module `R/disclosure-risk.R`:

- `assess_kanonymity(data, qi_cols, k = 5)` → list with:
  - `smallest_cell` (integer),
  - `n_below`, `pct_below` (records in combinations smaller than k),
  - `worst_cells` (tibble of the smallest QI-combinations and their counts).
  Pure, engine-independent, testable. Handles 0 QI cols (returns "no QIs"),
  1 QI col, all-unique, and `NA` values in QI columns.
- `privacy_check_pre()` calls it to add the missing **combination-level** flag.

## Enforcement — post-processing pass on the synthetic output

`enforce_kanon(synthetic, qi_cols, k)` runs inside `synthesize_data()` after
generation and shapes the **output artifact** until it satisfies the guarantee.
The coarsening ladder for each QI column is derived from its type (date →
day→month→year→decade; geography → finest→coarser unit; categorical → merge
rarest levels), so no separate plan argument is needed:

1. Remove / mask `direct` columns.
2. Cross-tabulate the QI columns; find cells with count in `[1, k)`.
3. **Coarsen loop**: apply the next generalization step to the synthetic QI
   columns directly (dates → coarser unit, geography → coarser unit, merge the
   rarest categorical levels), recount, and repeat until all cells ≥ k or the
   coarsening ladder is exhausted. No re-synthesis — we operate on the output.
4. **Floor suppression**: blank (`NA`) the QI values in any residual cells still
   below k.
5. Record the achieved granularity and any suppression as an attribute on the
   returned data, for the readout and the export report.

Reuse the existing coarsening primitives (date coarsening, geography coarsening,
rare-level merge) rather than inventing new ones.

## Readout / report

- **Pre** (Configuration, on the *original*): motivational only — "Released as-is
  at k=5 over {QIs}, N records (X%) would sit in unsafe combinations. Worst: …".
  Driven by `assess_kanonymity()`.
- **Post** (Generation / Compare, on the *synthetic* — the reviewer-facing
  headline): "✓ Synthetic data is 5-anonymous over {birth_date · zip · sex}.
  Smallest cell = 6. Coarsened: birth_date→year, zip→3-digit. Suppressed: 0
  cells." Driven by the `enforce_kanon()` result.
- `privacy_check_post()` gains the combination cell-size check (today it is
  single-column rare-category only).

## Testing

- `assess_kanonymity()`: crafted frames with known small cells; 0/1 QI columns;
  all-unique; `NA` handling; `pct_below` arithmetic.
- `enforce_kanon()`: after enforcement no QI-combination cell < k; coarsening is
  attempted **before** suppression; all-unique input forces full suppression;
  `direct` columns absent from output; granularity/suppression attribute recorded.
- `looks_aggregated()`: positive (count column + group structure) and negative
  (plain microdata) cases.
- `detect_roles()`: `disclosure_role` auto-assignment per the mapping;
  `sensitive` never auto-assigned.
- End-to-end: `synthesize_data()` with `k_anon = 5` → output passes the k-anon
  check and contains no `direct` columns.
- UI: editing a DISCLOSURE selector or the k field recomputes the readout.

## Migration / compatibility

- Removing the `sensitive` field is a breaking change to `dataganger_roles`.
  Update every consumer in the same change set; update tests that reference
  `sensitive`; regenerate man pages.
- Bump version after implementation (separate from this design).
