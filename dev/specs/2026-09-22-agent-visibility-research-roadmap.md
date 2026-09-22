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


## Funding targets (checked 2026-09-22)

Treat funding as support for the research program, not as a reason to collapse the
gates or overstate readiness.

### High-priority active / upcoming fits

1. **CANSSI Ontario — AI Applications in Statistical Sciences Research**
   - Up to $12,500 for one year.
   - Deadline: February 3, 2027.
   - Strong fit for the methodological core: using Laya/transformers to enhance
     statistical methodology, calibration, and privacy-risk decision modelling.
   - Candidate proposal: compare semantic decision models with interpretable
     statistical risk models and transparent ensembles for agent data access.

2. **University of Toronto DSI — Research Software Development Support Program**
   - Professional research-software developer support for 2-6 months.
   - Deadline: October 16, 2026.
   - Strong fit for hardening Which/DataGangeR integration, benchmark tooling,
     reproducible model artifacts, local inference, and open-source packaging.
   - This is in-kind software-development support rather than a cash research grant.

3. **University of Toronto DSI — Emergent Data Sciences Program**
   - $50,000-$100,000 over 1-2 years.
   - LOI deadline: November 20, 2026; full proposal February 19, 2027.
   - Best fit if framed as a broader U of T research/community program around
     privacy-preserving AI access to sensitive research data, with seminars,
     trainees, visitors, benchmarking, and cross-disciplinary collaboration.

4. **CANSSI Ontario — Data Access Grants**
   - Up to $5,000.
   - Rolling applications.
   - Fit only when a specific paid dataset is needed to develop/validate
     statistical methodology. It is not general project funding.

5. **NSERC Alliance Advantage / Alliance Society**
   - Alliance Advantage accepts applications with no deadline and supports
     partnered research; Alliance Society is aimed at science/engineering
     challenges with societal impact.
   - Potential fit for a larger phase if a credible public/not-for-profit/private
     partner contributes to the research and deployment problem.
   - Better as a scale-up target after seed evidence exists.

### Conditional / eligibility-dependent

6. **Banting-CANSSI Discovery Award in Biostatistics**
   - Up to $30,000 for one year.
   - 2026 cycle lists a November 2026 NOI and January 2027 application.
   - Only relevant if the applicant meets the new-investigator eligibility window
     and the project is anchored in biomedicine, occupational health, or
     environmental health.

### Watch for the next cycle

7. **Office of the Privacy Commissioner of Canada — Contributions Program**
   - Direct thematic fit with privacy and data-protection research.
   - The 2026-27 call closed February 20, 2026; the program issues calls annually
     and awards up to $100,000 per project.
   - Eligibility is at the organization level (not-for-profit organizations,
     including educational institutions), projects must be national in scope, and
     the primary focus must address private-sector privacy under the program's
     mandate.
   - Watch the next call rather than forcing the current research into the closed
     2026-27 theme.

8. **CANSSI Collaborative Research Teams**
   - Up to $210,000 over three years.
   - The 2026 deadline (May 22) has passed.
   - Strong future scale-up fit once there is a multi-institution statistical
     research team and the project has moved beyond proof-of-concept.

### Recently missed but strategically relevant

9. **U of T DSI Catalyst Grant**
   - Tier 1 up to $100,000; Tier 2 up to $50,000 for 1-2 years.
   - 2026 LOI deadline has passed.
   - Strong candidate for the next cycle after a seed benchmark exists.

10. **U of T DSI Data Access Grant**
    - Up to $10,000 for data-access costs.
    - 2026 deadline (September 15) has passed.
    - Relevant for a later validation dataset requiring paid access, not for
      general model/software work.

### Funding sequence

Recommended order:

```text
2026 fall:
  DSI Research Software Development Support
  + consider DSI Emergent Data Sciences

2026/27 winter:
  CANSSI Ontario AI Applications in Statistical Sciences
  + Banting-CANSSI only if eligibility fits

rolling:
  CANSSI Ontario Data Access when a concrete paid dataset is identified
  NSERC Alliance once a partner and larger research plan are ready

next calls:
  OPC Contributions Program
  DSI Catalyst
  CANSSI CRT
```

The first grant application should fund a bounded scientific question, not the
entire long-term architecture. A good seed question is:

> Can semantic typed-decision models and interpretable statistical models provide
> independently useful, calibrated evidence for deciding when research data
> require transformation or human review before exposure to an AI agent?
