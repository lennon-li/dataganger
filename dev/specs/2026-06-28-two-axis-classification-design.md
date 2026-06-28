# Two-Axis Column Classification — Design (2026-06-28)

Supersedes the single-dropdown disclosure model from
`2026-06-27-configure-classification-questions-design.md`.

## Problem

The shipped Configure page asks one mutually-exclusive question per column with
four options (direct / quasi / sensitive / "measure"). Real columns violate
mutual exclusivity:

- `smoking_status` is **quasi-identifying** AND a **sensitive fact** AND an
  **analytic outcome** — all at once.
- "Measure / metric" is not a disclosure property; it is analytic intent. A
  measurement can itself be a private fact (income, a lab value), so "private
  fact" vs "measurement" reads as a false choice.

Forcing one label discards true information and confuses users. It also produced
a real bug: the on-screen example for "quasi" lists *age*, so users classify a
numeric analytic variable as a quasi-identifier; k-anonymity then coarsens it
into `(37,44]` / `(other)` / `NA` bins ("age is NULL").

## Model

Two **independent** questions per column, each intrinsic to how a user already
understands their data. The treatment is **derived**, never chosen.

**Q1 — Does this point to a person?** (`identifies`)
- `none` — doesn't single anyone out.
- `combination` — not unique alone, but identifying combined with other columns
  (age, sex, ZIP, birth date, job title).
- `direct` — names the person on its own (name, email, SSN, record id).

**Q2 — Is it sensitive?** (`sensitive`, logical)
- `FALSE` — no.
- `TRUE` — would harm/embarrass if linked back (diagnosis, income, religion).

### Derived action grid (shown live in "What we'll do")

|              | sensitive = No                                  | sensitive = Yes                                      |
|--------------|-------------------------------------------------|------------------------------------------------------|
| identifies none        | Synthesized; distribution kept, exact values not. | Synthesized; protected from linkage.                |
| identifies combination | Coarsened & grouped (k-anonymity), then synthesized. | Coarsened & grouped + protected from linkage.   |
| identifies direct      | **Removed** from the output.                     | **Removed** from the output.                        |

Direct always drops (sensitivity irrelevant). Everything non-direct is
synthesized, so a sensitive outcome like `smoking_status` survives for analysis.

## How it feeds the simulation (the contract)

`disclosure_role` (single value) is consumed in 9 places: `enforce_kanon`,
`privacy_check`, `export-synthetic`, `make-agent-bundle`, `export-diagnostic`,
`mod-generate` recap, the Generate gate, and the CLI spec-YAML round-trip. We do
not remove it.

- **Source of truth:** two new roles columns, `identifies` and `sensitive`.
- **`disclosure_role` becomes a derived projection** of the axes, kept on the
  roles object so every existing consumer and the CLI YAML contract are
  unchanged:
  - `identifies == "direct"` -> `"direct"`
  - `identifies == "combination"` -> `"quasi"`
  - else `sensitive` -> `"sensitive"`
  - else -> `"none"`
- **One behavior change:** `dg_kanon_columns()` reads the axes directly so it
  captures the overlap a single value cannot:
  `QI = {identifies == "combination"} ∪ {sensitive & discrete class}`.
  This fixes combination+sensitive on a numeric column (e.g. income), which the
  old projection would have dropped from k-anon.
- `enforce_kanon` keeps dropping `disclosure_role == "direct"` (derives cleanly).
- `simulation` (synthesize/drop/pass_through) keeps deriving from the action:
  `identifies == "direct"` -> `"drop"`, else `"synthesize"`. Advanced override
  unchanged.

## Migration (existing roles / CLI specs)

Back-fill axes from any pre-existing `disclosure_role`:
- `direct` -> identifies=direct, sensitive=FALSE
- `quasi` -> identifies=combination, sensitive=FALSE
- `sensitive` -> identifies=none, sensitive=TRUE
- `none`/`""`/NA -> identifies=NA (unset), sensitive=FALSE

CLI YAML still accepts `disclosure_roles: {col: direct|quasi|sensitive|none}`;
applying an override back-fills the axes the same way.

## Gate / defaults

- A column "needs an answer" when `identifies` is unset (NA/""). This keeps the
  Generate gate's friction on the one question that determines whether a column
  is dropped or coarsened.
- `sensitive` defaults to `FALSE` and is always visible as a second control.
  Auto-detection may pre-set `sensitive = TRUE` for name-matched columns
  (current `is_sensitive_name` heuristic) and `identifies` from class
  (`dg_suggest_disclosure` re-expressed onto the axes).

## Page layout

The two questions move to the **top of Configure, inline** (not folded in a
`<details>`), each with one example line. The per-column table gains a second
select; "What we'll do" stays the derived column:

```
Column          Points to a person?       Sensitive?   What we'll do
record_id       [ Directly       ▾ ]      [ No  ▾ ]    Removed from output
age             [ Only combined  ▾ ]      [ No  ▾ ]    Coarsened (k-anon), synthesized
smoking_status  [ Only combined  ▾ ]      [ Yes ▾ ]    Coarsened + linkage-protected
bmi             [ No             ▾ ]      [ No  ▾ ]    Synthesized; distribution kept
```

## Coarsening quality fix (the visible bug)

Independent of the model: numeric k-anon coarsening must read as clean ordered
ranges (`[20,37] (37,44] (44,51]`), and suppression-blanked cells must not look
like silent corruption. Add a regression test that classifies `age` as
combination on `example_health_survey`, runs synth -> compare -> privacy ->
export -> the Generate recap render, and asserts no error and no all-NA column.

## Docs

The derived-action grid goes into the manual: `getting-started.Rmd` "## 3.
Configure", `README.md`, and the in-bundle `README.md` so humans and agents read
the same mapping.
