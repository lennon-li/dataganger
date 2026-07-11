# Package index

## Data Input and Profiling

Read data from files and compute a statistical profile. These functions
are the first step in the DataGangeR workflow.

- [`read_input()`](https://dataganger.biostats.ai/reference/read_input.md)
  : Read a data file into a tibble
- [`profile_data()`](https://dataganger.biostats.ai/reference/profile_data.md)
  : Profile a dataset column-by-column
- [`looks_aggregated()`](https://dataganger.biostats.ai/reference/looks_aggregated.md)
  : Heuristic: does this data frame look pre-aggregated (a table of
  counts)?

## Column Role Detection

Detect each column’s two intrinsic disclosure axes — whether it
identifies a person (none / combination / direct) and whether it is
sensitive — plus synthesis roles. The app treats these two axes as the
source of truth; the CLI still accepts `disclosure_roles:` as a
compatibility mapping.

- [`detect_roles()`](https://dataganger.biostats.ai/reference/detect_roles.md)
  : Detect data roles for each column
- [`suggest_min_rows()`](https://dataganger.biostats.ai/reference/suggest_min_rows.md)
  : Suggest a sufficient synthetic row count

## Synthesis Specification

Define how the synthetic data should be generated — purpose, fidelity,
row count, engine, seed, and disclosure settings.

- [`synth_spec()`](https://dataganger.biostats.ai/reference/synth_spec.md)
  : Create a synthesis specification

## Synthesis

Synthesize a dataset from a real data frame.

- [`synthesize_data()`](https://dataganger.biostats.ai/reference/synthesize_data.md)
  : Synthesize a data double

## Comparison

Compare a synthetic dataset against its original using distribution and
relationship-interaction tests to assess fidelity.

- [`compare_synthetic()`](https://dataganger.biostats.ai/reference/compare_synthetic.md)
  : Compare original and synthetic datasets
- [`plot_comparison()`](https://dataganger.biostats.ai/reference/plot_comparison.md)
  : Plot comparison summaries

## Disclosure and Privacy

Assess and enforce k-anonymity and other disclosure-risk properties.
Synthetic outputs reduce direct disclosure risk but do not provide a
formal privacy guarantee.

- [`privacy_check()`](https://dataganger.biostats.ai/reference/privacy_check.md)
  : Run disclosure-risk privacy checks
- [`assess_kanonymity()`](https://dataganger.biostats.ai/reference/assess_kanonymity.md)
  : Assess k-anonymity over a set of quasi-identifier columns
- [`enforce_kanon()`](https://dataganger.biostats.ai/reference/enforce_kanon.md)
  : Enforce k-anonymity on a synthetic dataset (output guarantee)

## Export and Bundles

Export synthetic data and create agent bundles for sharing with
collaborators or AI programming tools.

- [`export_synthetic()`](https://dataganger.biostats.ai/reference/export_synthetic.md)
  : Export a synthetic data bundle
- [`export_diagnostic_package()`](https://dataganger.biostats.ai/reference/export_diagnostic_package.md)
  : Export a Lens-compatible diagnostic schema for a dataset
- [`make_agent_bundle()`](https://dataganger.biostats.ai/reference/make_agent_bundle.md)
  : Create a one-command agent-ready bundle from a raw data file
- [`check_code_readiness()`](https://dataganger.biostats.ai/reference/check_code_readiness.md)
  : Check whether synthetic data is code-compatible with the original

## Feedback

Report a problem or suggest a feature via a pre-filled GitHub issue.

- [`report_issue()`](https://dataganger.biostats.ai/reference/report_issue.md)
  : Report a problem or share feedback

## CLI

Command-line interface entry point.

- [`dataganger_cli()`](https://dataganger.biostats.ai/reference/dataganger_cli.md)
  : DataGangeR command-line interface

## Shiny App

Launch the interactive DataGangeR Shiny application.

- [`run_app()`](https://dataganger.biostats.ai/reference/run_app.md) :
  Launch the DataGangeR Shiny Application

## Example Datasets

Small synthetic datasets included in the package for use in examples,
tests, and learning the workflow without real data.

- [`example_health_survey`](https://dataganger.biostats.ai/reference/example_health_survey.md)
  : Example health survey dataset
- [`example_admin_claims`](https://dataganger.biostats.ai/reference/example_admin_claims.md)
  : Example administrative claims dataset
- [`example_registry`](https://dataganger.biostats.ai/reference/example_registry.md)
  : Example disease registry dataset
- [`individual_sample`](https://dataganger.biostats.ai/reference/individual_sample.md)
  : Individual-level synthetic sample data
- [`temporal_sample`](https://dataganger.biostats.ai/reference/temporal_sample.md)
  : Temporal synthetic sample data
- [`geographic_sample`](https://dataganger.biostats.ai/reference/geographic_sample.md)
  : Geographic synthetic sample data
