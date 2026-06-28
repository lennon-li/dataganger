# Configure page: intrinsic per-column classification questions

**Date:** 2026-06-27
**Status:** Design approved (pending written-spec review)
**Scope:** Redesign how the Configure step elicits per-column disclosure
classification. Per-column only — the objective preset remains the single
global trade-off dial (out of scope here).
**Baseline:** Builds on `fix/synthesis-settings-labels` (single Protection
meter on the objective page; the disclosure role formerly called "None" already
relabelled "Measure / metric").

---

## 1. Problem & contribution framing

The synthesis engine (synthpop, k-anonymity, coarsening) is borrowed and
well-understood. DataGangeR's contribution is the **specification protocol**: a
faithful translation of the statistical-disclosure-control parameter space into
a few decisions a non-expert human — or an AI agent — can make in seconds,
without ever silently producing an unsafe spec.

The Configure step is where that translation is most load-bearing and currently
weakest: it presents a four-way disclosure dropdown (`measure` / `direct` /
`quasi` / `sensitive`) whose terms users don't reliably understand, and a
separate action control (`synthesize` / `pass_through` / `drop`). Users stall
because they're asked to reason in privacy jargon.

Three properties any redesign must preserve (the bar that makes this a
contribution, not just a nicer form):

1. **Faithful** — no combination of easy answers yields a theoretically wrong
   or unsafe spec; unset = protected, never exposed.
2. **Minimal** — the fewest questions that still determine the spec; never ask
   what the tool can infer.
3. **Transparent** — the user can see what each plain answer *implies* in
   theory and in treatment.

## 2. Decisions captured (scope)

In scope (per-column):
- **Classification** — which of four privacy categories the column is.
- **Action** — `synthesize` / `pass_through` / `drop`. **Derived** from the
  classification, not asked (advanced override available).

Out of scope (unchanged):
- Global synthesis trade-off (coarsening depth, relationship preservation,
  k level, missingness, name handling) — stays in the **objective** preset.

## 3. The per-column control

One dropdown per column. Options are privacy/identifiability categories,
ordered most-identifying → least, each led by a privacy concept with concrete
examples. Privacy-first, not data-first: the wording teaches users to think in
terms of identifiability and sensitivity (most don't know "PII/PHI"), while the
examples let them self-sort by recognition.

The four options and their faithful mapping:

| Option (what the user picks) | examples | internal role | derived action / treatment |
|---|---|---|---|
| **Identifies a person directly** | name, email, phone, address, SSN, record/account number | `direct` | removed from output |
| **Helps identify in combination** | age, sex, ZIP/postcode, race, birth date, job title, rare/unique codes | `quasi` | coarsened + k-anonymity, then recreated |
| **Is a private or sensitive fact** | diagnosis, test result, income, medication, religion, sexual orientation | `sensitive` | recreated synthetically; protected from linkage |
| **Is a measurement or value you analyze** | blood pressure, lab value, score, count, price, quantity, outcome | `none` (measure) | recreated synthetically (distribution kept, exact values not) |

- The four map 1:1 to existing internal `disclosure_role` values, so engine
  logic is unchanged.
- The **action is shown as a derived consequence** (read-only), never chosen in
  the normal flow.

## 4. The decisions table (transparency + override)

The Configure page is one table; the user's answer and the resulting decision
sit side by side and update live:

```
Column        This column is…                 What we'll do (based on your answer)
patient_name  Identifies directly        [▼]  Removed — not in the synthetic data        [⋯]
age           Helps identify in combo    [▼]  Coarsened & grouped so no one is unique,
                                              then recreated (k-anonymity)               [⋯]
diagnosis     Private / sensitive        [▼]  Recreated synthetically; protected from
                                              linkage                                    [⋯]
cholesterol   Measurement / value        [▼]  Recreated synthetically; distribution kept [⋯]
notes         — not set —                [▼]  ⚠ needs an answer before you can generate

No exact original record is ever copied — only structure and distributions carry over.
```

- **Middle column = input** (the privacy-first dropdown); **right column = live
  consequence** — transparency is continuous, never a guess.
- **Two override levels:**
  1. *Re-answer* — change the dropdown (normal path).
  2. *Advanced override* — the `[⋯]` per row reveals a manual action override:
     force **drop**, or **keep original values (pass-through)**. Pass-through
     copies real values, so it carries an inline warning and is never a default.
     Collapsed by default to keep the simple path simple.
- The existing **read-only recap on the Generate page stays** as the final
  "this is exactly what will run" confirmation. Transparency appears twice:
  editable here, locked there.

## 5. Explaining the four classes (three layers)

1. **Inline examples** — always visible beneath each dropdown option (Section
   3 table). Most columns are resolved here by recognition.
2. **"What do these mean?" panel** — persistent, collapsed by default. Leads
   with the two questions that are the whole mental model, then defines each
   class with fuller examples:
   - *Could a value point to a specific person?* → identifying (directly, or in
     combination).
   - *Would it harm someone if it leaked?* → sensitive.
   - Bridge line: "Identifying + sensitive columns together are what rules call
     PII / PHI."
   - When-unsure rule: "Pick the more protective option. A value that's unique
     or rare in your data (a long ID, an exact salary) counts as identifying."
3. **Per-row "why we suggested this" hint** — small muted text / hover showing
   the detection reason (e.g. *"suggested: looks like an ID — every value is
   unique"*; *"suggested: 6 distinct values — looks categorical"*). Makes the
   pre-fill trustworthy and quietly teaches the logic.

## 6. Defaults, pre-fill, and the gate

`detect_roles` sets the initial dropdown per column, biased **protective**:

| Structural signal | Suggested option | Rationale |
|---|---|---|
| Unique / high-cardinality text, free text | Identifies directly | high re-id risk → remove |
| Date | Helps identify in combination | birth dates etc. are classic quasi-IDs |
| Continuous numeric | A measurement or value | conservative: a distinctive number is not assumed to be an ID |
| Low-cardinality categorical (ambiguous: trait vs category) | **left unset** | structure can't tell sex (quasi) from treatment-arm (measure) → ask |
| Logical / boolean | A measurement or value | |

- Every pre-fill is a *reviewable suggestion* (shows its why-hint), never a
  silent decision.
- **Gate (safe-by-default):** any column left unset blocks generation —
  *"3 columns still need an answer before you can generate."* Unknown =
  protected, never exposed.

## 7. Edge cases

- **Both identifying and sensitive** (religion, pregnancy, sexual orientation:
  narrows down *who* and is private). A single-select 4-way can't express the
  (identify + private) corner of the 2×2. **Resolution: keep 4 options +
  auto-union the protections.** The user picks "Private or sensitive"; if the
  column is also identifying (detected, or in the quasi set), the engine layers
  quasi protection on top. The "what we'll do" cell then reads *"Recreated &
  protected from linkage; also grouped for k-anonymity."* One pick, safe result,
  union shown transparently.
- **Direct vs quasi by uniqueness** — decided by cardinality, not asked. An "ID
  candidate" detection surfaces as a suggested "Identifies directly" with its
  why-hint; the user can downgrade if it is actually a measure.
- **Free text** → suggested "Identifies directly" (removed), since free text
  commonly embeds identifiers.

## 8. Faithfulness summary (the contract)

- Each option has exactly one theoretical referent (Section 3 table).
- The mapping is **total** over the four options and **safe-by-default** for
  the unset state.
- The only place two protections combine is the documented auto-union for
  sensitive-and-identifying columns — and it is surfaced, not hidden.
- No user answer can produce silent exposure: worst case is over-protection
  (a measure marked identifying → removed/coarsened), which is safe.

## 9. High-level code impact (for the implementation plan)

- `R/mod-roles.R` — replace the disclosure dropdown labels/structure with the
  four privacy-first options + inline examples; build the decisions table
  (input + live "what we'll do" column); per-row why-hint; advanced override
  affordance; evolve `disclosure_help_ui()` into the three-layer help. Reuse
  the shared `dg_disclosure_label()` (from baseline).
- Action derivation — a single mapping `disclosure_role (+ objective) → action`,
  replacing the separate user-set `simulation` control; advanced override still
  writes `simulation` directly.
- Auto-union logic — when `disclosure_role == "sensitive"` and the column is
  also identifying, include it in the k-anonymity / coarsening set.
- Gate — unchanged in spirit (unset blocks); update copy.
- Pre-fill mapping — `detect_roles` class → suggested option, with ambiguous
  low-card categoricals left unset.
- Tests — `test-mod-roles.R` (new option set, derived action, auto-union,
  unset-gate), `test-mod-generate.R` (recap still renders labels).

## 10. Non-goals

- No change to the objective preset or the global synthesis knobs.
- No new disclosure category beyond the existing four (auto-union covers the
  both-case).
- No l-diversity / t-closeness implementation for sensitive columns (noted as
  future work; today sensitive is protected from linkage + flagged).
- Visual styling/layout is a separate task.
