# Design brief — guardrail gate, comparison-stats redesign, agent skill file

Status: DRAFT (design discussion with Lennon, 2026-06-29). Decisions for the guardrail are
firm; comparison-stats and agent-skill sections capture Lennon's intent + open questions and
are not yet fully discussed. No code written yet.

Builds on the existing two-axis model (`identifies` + `sensitive`) — see
`dev/specs/2026-06-28-two-axis-classification-design.md`. In the Configure UI:
- **Question 1 = the "points to a person" axis (`identifies`).**
- **Question 2 = the sensitivity axis (`sensitive`).**
(These labels were ambiguous before; pin them in the UI copy.)

---

## 1. Direct-identifier guardrail + fail-safe  (DECIDED)

### Intent
A consent/guardrail gate so users explicitly attest the dataset has no direct identifiers
before synthesis, plus a disclaimer that the app does not keep data and is used at own risk.

### Entry gate (hard)
- Before proceeding, the user must agree: **"By using this app I confirm there are no direct
  identifiers, including institutional identifiers, in this dataset."**
- Give concrete examples: **email, name, healthcare/medical record number, SSN/national ID,
  institutional ID, phone number, address.**
- **Agree → proceed. Refuse → refuse to advance and shut the app down.**

### Disclaimer (precise wording matters)
The disclaimer must distinguish *reading* from *keeping*, so the fail-safe (which reads the
file) does not appear to contradict it:

> "Your data is processed **locally on your machine, in memory only**. It is never uploaded,
> never sent anywhere, and never written to disk by this app. Nothing is retained after you
> close it. Use at your own risk."

Rationale: the app *must* read the data into memory to profile/detect/synthesize — that is
unavoidable and is not a privacy concession. "Processed locally / in memory / not kept" is
fully consistent with detection running on the data.

### Effect on Question 1 options (DECIDED)
After the user attests "no direct identifiers", **Question 1 collapses from three options to
two**:
- Before attestation (or non-gated mode): `none` / `combination` / `direct`
- After "yes, no direct identifiers": **`none` / `combination`** only (drop `direct`).

Reason: `direct` would contradict the attestation. This makes the gate *mean something*
downstream instead of being a one-time checkbox.

Question 2 (sensitivity) is unchanged — the attestation says nothing about sensitivity.

### Soft detection fail-safe (DECIDED)
- After read → profile → detect, if the detector flags columns that look like direct
  identifiers **despite the attestation**, surface **exactly which columns and why**
  (e.g. "`email` looks like an email address", "`mrn` is high-cardinality and ID-shaped").
- Ask **"Are you sure these aren't identifiers?"** with three actions:
  **confirm & proceed**, **drop these columns**, or **abort**.
- This is a *softer* checkpoint than the entry gate: mid-flow discovery offers drop/confirm,
  **not** shutdown. (Punishing an honest user who finds one identifier with a shutdown trains
  people to click through the gate carelessly.)
- Detection already runs (`detect_roles`); the fail-safe only surfaces what it computed — no
  new data exposure.

### Framing guardrails (non-negotiable)
- **Do not promise the net catches everything.** The detector is heuristic and conservative
  — false negatives (a plain numeric MRN won't trip it) and false positives both exist. Frame
  it as *assistive*: "We flagged some columns that might point to a person. You are still
  responsible for confirming." Anything stronger is a false safety claim and breaks the
  package's "reduce risk, not guarantee" principle.

### Decided
- The entry attestation is **informed consent**, and mid-flow detection is the **soft**
  checkpoint (show findings → are you sure? → drop / confirm / abort; **no shutdown**). The
  stricter "hard re-gate" alternative (mid-flow detection re-triggers the entry gate / shutdown)
  is **rejected** — it would punish honest users and train careless click-through.

---

## 2. Comparison-stats redesign  (intent captured; not fully discussed)

In the Compare view, replace the current per-metric deltas with inference-aware statistics:

| Metric | Displayed statistic | Color-coded by |
|--------|--------------------|----------------|
| Mean   | **Standardized mean difference** (replace raw delta) | p-value (two-sample test) |
| SD     | **Ratio** (synthetic / original) | **F-test** p-value (variance ratio) |
| Median | **robust standardized location difference** `(median_syn - median_orig) / IQR_orig` | **Mann-Whitney (Wilcoxon rank-sum)** p-value |
| Min    | value only | **no inference** |
| Max    | value only | **no inference** |

**Color = p-value (DECIDED).** The displayed number carries the effect size (SMD / ratio);
the color carries significance. A *significant difference* = poor fidelity, so low p → red/bad,
high p → green/good (confirm exact thresholds + palette).

Threshold note (not a reopen): p is sample-size-driven — at very large n almost everything
reads "significant", at very small n almost nothing does; color is most informative at moderate
n, and the user reads the number (effect size) for the rest. Pick thresholds with this in mind.

### Median (DECIDED)
Median is a **location** measure (like the mean), not a spread measure (like SD), so it
mirrors the mean's treatment robustly:
- **Display:** robust standardized location difference `(median_syn - median_orig) / IQR_orig`
  (use IQR, or MAD, of the original as the robust scale). Chosen over a raw median ratio
  because a ratio breaks at median ~ 0 or negative (centered/standardized columns).
- **Color:** **Mann-Whitney / Wilcoxon rank-sum** p-value. (Tests location/stochastic shift,
  not the median per se; more powerful and standard than Mood's median test.)

### Open
- Confirm which columns this applies to (numeric only; categoricals already use a different
  comparison).

---

## 3. Agent skill file  (intent captured; not fully discussed)

README is **human-only**. Add a separate **agents-only** instruction file, authored as a
**skill file** ("how to use this package"), flexible rather than rigid.

### Hard rules for the agent
- **FIRST LINE / ITEM OF SKILL.md (verbatim intent): "You are not allowed to read the original
  data."** This is the lead rule, stated before anything else.
- The agent's only interaction with real data is to **call the package / CLI** (with the user's
  UI-provided settings) to generate synthetic data or variations — it never opens or inspects
  the real data itself.
- **Column names may vary slightly** from the original data — build in a guardrail so the agent
  does not assume exact original names (robust to renaming via name strategies).

### Scenario (DECIDED)
This skill addresses the **generation** scenario:
- The agent **may run R / the CLI on the real data**, using the **settings the user configured
  in the UI** (the exported spec + seed). But the agent **never reads / inspects the real data
  itself** — it only passes it to the package. ("Not allowed to touch real data, only call the
  package with the user's settings.")

### Required first step — UI-vs-CLI parity check (DECIDED)
- The user first generates a synthetic CSV **via the UI** (this is the reference / ground truth).
- The agent's first action is to **regenerate via the CLI using the user's exported settings
  (spec + seed)** and assert its output CSV is **identical to the UI-generated CSV**.
- Purpose: prove the agent has correctly **learned/applied the user's settings** and that the
  pipeline is deterministic across UI -> CLI, *before* it generates any variations.
- Implies a requirement to honor: **UI and CLI must produce byte-identical output given the
  same spec + seed + data.** The UI must export its exact spec (including seed) for the agent to
  run. If they ever diverge, this check is exactly what catches it.
  - Exact step: UI exports `spec.yaml` (with seed) + `synthetic_data.csv` -> agent runs
    `dataganger synthesize <real-data> --spec spec.yaml --out ...` -> compare the agent's
    `synthetic_data.csv` to the UI's -> assert identical -> only then proceed.

### PARITY GAP (must fix for the reproduce check to pass) — found 2026-06-29
The UI does **not** call the CLI. Both front-ends call the same synthesis **engine**
(`synthesize_data()`), so identical inputs give identical output — but they **assemble the
inputs differently**:
- **UI** feeds the user's full per-column decisions: `run_synthesis_pipeline(data, spec,
  roles = state$roles)` -> `synthesize_data(..., roles = state$roles)`. `state$roles` carries
  the complete two-axis (`identifies` + `sensitive`) + action/simulation choices.
- **CLI** (`cli_cmd_synthesize`) **re-detects roles**: `detect_roles(data)` +
  `apply_disclosure_overrides(roles, disclosure_roles)`. It only honors the narrow
  `disclosure_roles:` map from the spec YAML — NOT the user's full two-axis + action choices.

Consequence: whenever the user's UI choices differ from what `detect_roles` + `disclosure_roles`
reproduce, the CLI gets **different roles** -> different drops/coarsening -> **different output**
-> the reproduce check FAILS even though nothing is "wrong."

Required changes to make parity hold:
1. **UI export must include the full roles** (the user's per-column two-axis + action decisions
   + seed), e.g. a `roles.yaml`, not just `disclosure_roles`.
2. **`dataganger synthesize` must accept `--roles roles.yaml` and consume it verbatim**,
   bypassing `detect_roles()` when roles are supplied.
3. Then UI and CLI both call `synthesize_data()` with identical data + spec + roles + seed ->
   byte-identical output -> the agent's parity check passes.

(There is already a `dataganger roles` command and the engine accepts `roles`; the missing
piece is a `--roles` input to `synthesize` and a UI export of the complete roles.)

### Location (DECIDED)
- **`inst/agent-skill/SKILL.md`** — installed with the package, discoverable in any install.
- Referenced from the human README ("agents: see this skill").
- Add a **`dataganger skill`** CLI command to print/emit the skill file.
- The per-bundle `inst/templates/ai-readme.md` stays as the in-bundle note; the new SKILL is the
  **package-usage** guide (distinct purpose).

### Other invariants
- **Column names may vary** from the original (name strategies: preserve / generic /
  dictionary_only). The agent must be robust to renaming, not assume original names.
- Tone: flexible "how to use this package" guide, with the hard rules above as invariants.

### Found defect (to fix when authoring)
- The current `inst/templates/ai-readme.md` lists **dropped columns as `- NA (NA)`** in the
  Variables section (observed in a real bundle: `patient_id`/`lab_value` rendered as `NA (NA)`).
  Dropped columns should either be omitted from Variables or shown under "Dropped" only — not
  leaked as `NA` placeholders. Fix as part of the agent-file work.

---

## Sequencing (proposed, for later)
1. Guardrail + Question-1 collapse + disclaimer (decisions firm; smallest, highest-trust).
2. Agent skill file (mostly authoring; needs the reproduce-target defined).
3. Comparison-stats redesign (needs the p-value-vs-effect-size design decision first).
