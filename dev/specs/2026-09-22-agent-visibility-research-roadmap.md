# Research roadmap: Can an AI agent safely see this data?

Date: 2026-09-22
Status: gated research plan; no production safety claim

## Research question

Develop and validate an auditable decision layer for the question:

> Given a dataset, a proposed agent task, and a defined threat model, what is the
> risk of exposing the relevant data to that agent?

Do not encode this initially as an absolute "safe/unsafe" truth. The first
research target should be a calibrated, threat-model-specific
`agent_exposure_risk` outcome such as low / uncertain / high, or a probability
of a defined material privacy/disclosure event.

## Boundary between Which and DataGangeR

### Which

Which is reusable decision infrastructure. It owns:

- engine adapters and capability contracts for Jev, Laya, and future engines;
- typed question / decision specifications;
- normalized labels, probabilities, confidence, and abstention;
- engine-neutral benchmark formats;
- train/calibration/test split helpers;
- calibration and threshold-fitting utilities;
- Brier/ECE/coverage/accepted-accuracy evaluation;
- engine comparison reports;
- model/checkpoint/calibration artifact manifests;
- generic import/export adapters such as the Obsidian Hermes/Jev experiment log.

Which must not own:

- the definition of privacy or disclosure risk;
- DataGangeR-specific privacy labels;
- rules that decide whether a dataset may be released to an agent;
- DataGangeR UI, synthesis, or disclosure-control behavior.

### DataGangeR

DataGangeR owns the domain and policy:

- privacy threat model;
- deterministic direct-ID, quasi-ID, sensitive-field, free-text, exact-match,
  k-anonymity, and disclosure diagnostics;
- construction of bounded local column/dataset summaries;
- annotation rules for `identifies`, `sensitive`, semantic role, and
  `agent_exposure_risk`;
- public/synthetic benchmark case construction;
- reconciliation of deterministic, semantic, and statistical evidence;
- human review and fail-closed behavior;
- `ai_safe()` / `dataganger ai-safe` if the research eventually supports it.

DataGangeR may use Which as an optional dependency or external decision service,
but its default behavior must remain local/no-network and useful without Which.

## Three distinct models/questions

Keep these separate until evidence justifies combining them.

### 1. Semantic classification

Question: what kind of data is this?

Candidate engine: Laya, with Jev as a comparison engine.

Example outputs:

- identifies: none / combination / direct;
- sensitive: true / false;
- semantic role: identifier / geography / health / financial / free text /
  measurement / coded category / other.

### 2. Statistical agent-exposure risk

Question: given measurable dataset properties and the requested agent operation,
what is the probability/risk of a defined privacy or disclosure failure?

Start with interpretable statistical models: penalized logistic/ordinal
regression or GAM before complex ML.

Candidate features:

- record and variable counts;
- direct/quasi/sensitive counts;
- uniqueness and maximum distinct ratios;
- minimum equivalence-class size;
- rare-category prevalence;
- free-text presence;
- date/geographic precision;
- combination uniqueness;
- missingness/entropy/cardinality summaries;
- original vs synthetic;
- requested operation (schema inspection, row inspection, analysis, export);
- deterministic privacy flags.

The outcome must be formally defined before fitting. Generic PII labels are not
the same as "safe for an AI agent to inspect."

### 3. Policy

Question: what should DataGangeR do with the evidence?

Initially this remains explicit deterministic policy plus a human gate:

- allow bounded access;
- transform/synthesize/redact first;
- human review;
- block.

A favorable model score never overrides a deterministic hard blocker by itself.

## Gated roadmap

### Gate 1 — Which infrastructure

Current priority.

Use Hermes + the existing Obsidian Jev advisor to build Which and collect real,
prospective decisions.

Exit criteria:

- same labeled cases reproducibly run through a versioned decision spec;
- blind labels and outcomes are retained;
- calibration/evaluation is engine-neutral;
- held-out testing is supported;
- Jev can move out of Obsidian without loss of the generic decision layer.

No DataGangeR Laya training or safety ensemble before this gate.

### Gate 2 — Jev/Laya parity in Which

Run Jev and Laya against the same delegation benchmark.

Exit criteria:

- common normalized outputs;
- separately calibrated probabilities;
- fixed held-out test set;
- latency/cost and accuracy/coverage comparison;
- engine-specific artifacts remain separable from the gold labels.

### Gate 3 — DataGangeR semantic benchmark

Build a public/synthetic benchmark, initially about 1,000–2,000 curated cases.

Sources may include public/synthetic PII corpora, Presidio-style examples,
public tabular datasets, generated hard negatives, and generated
combination-risk scenarios.

Compare:

A. current deterministic role detector;
B. stock Laya;
C. calibrated Laya;
D. deterministic + calibrated Laya;
E. Jev on the same spec where useful.

Primary metrics:

- direct-identifier false-negative rate;
- sensitive-field false-negative rate;
- specificity / false-positive review burden;
- balanced accuracy;
- Brier score and ECE;
- coverage and accepted-case accuracy at abstention thresholds.

Exit criterion: Laya must add useful information beyond the deterministic
baseline on an untouched test set.

If it does not, stop; do not fine-tune merely because open weights are available.

### Gate 4 — optional Laya domain adaptation

Only after Gate 3.

Use reviewed human labels, outcome-backed corrections, and public/synthetic
training cases. Never use Jev predictions as automatic teacher labels.

Track:

- base checkpoint;
- corpus version/hash and licenses;
- training parameters/seed;
- calibration artifact;
- held-out metrics;
- model card and intended-use limitations.

Weights live outside the CRAN package.

### Gate 5 — define the statistical risk estimand and dataset

This is a separate research project.

Before modelling, define a threat-model-specific endpoint. Candidate framing:

`P(material identification or sensitive-attribute disclosure | dataset summary,
agent operation, access boundary)`.

Develop public/synthetic attack or disclosure scenarios and expert-reviewed
labels. Keep the test set frozen.

Exit criterion: an interpretable statistical model shows useful discrimination
and calibration beyond deterministic rules.

### Gate 6 — ensemble only if independently justified

Do not build an ensemble until both the semantic model and statistical model
independently add value.

Compare on the same held-out set:

A. deterministic only;
B. Laya only;
C. statistical only;
D. deterministic + Laya;
E. deterministic + statistical;
F. deterministic + Laya + statistical.

Only retain F if it materially improves over D and E on pre-specified privacy
metrics, not merely overall accuracy.

Start with transparent fusion rules or a small interpretable meta-model rather
than an opaque learner.

### Gate 7 — DataGangeR product integration

Only after prospective validation.

Possible optional API:

```r
ai_safe(
  data,
  task = "analysis",
  semantic_engine = "laya",
  risk_model = "dataganger-risk-v1"
)
```

Requirements:

- default DataGangeR remains functional with no network/model dependency;
- local inference preferred;
- raw data are never sent to remote engines;
- bounded/versioned summaries only;
- deterministic hard blockers cannot be silently downgraded;
- uncertainty/conflicts trigger review;
- output records model/spec/calibration versions;
- no claim of anonymity, regulatory compliance, or universal safety.

## Funding-ready project framing

Potential project title:

**Auditable Statistical and Semantic Gates for Privacy-Preserving AI Access to
Research Data**

Research aims:

1. Formalize agent-exposure risk under explicit access/threat models.
2. Develop interpretable statistical predictors of disclosure risk from bounded
   dataset summaries.
3. Evaluate open typed-decision models for semantic privacy classification.
4. Develop and validate transparent fusion/abstention rules.
5. Deliver open benchmarks, software, and reproducible calibration artifacts
   through Which and DataGangeR.

This framing separates methodological research from software engineering and is
suitable for statistical/data-science/privacy funding calls.
