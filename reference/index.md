# Package index

## Data Input and Profiling

Read data from files and compute a statistical profile. These functions
are the first step in the DataGangeR workflow.

- [`read_input()`](https://lennon-li.github.io/dataganger/reference/read_input.md)
  : Read a data file into a tibble
- [`profile_data()`](https://lennon-li.github.io/dataganger/reference/profile_data.md)
  : Profile a dataset column-by-column
- [`looks_aggregated()`](https://lennon-li.github.io/dataganger/reference/looks_aggregated.md)
  : Heuristic: does this data frame look pre-aggregated (a table of
  counts)?

## Column Role Detection

Detect each column’s two intrinsic disclosure axes — whether it
identifies a person (none / combination / direct) and whether it is
sensitive — plus synthesis roles. Used on the Configure page and in the
CLI `disclosure_roles:` spec.

- [`detect_roles()`](https://lennon-li.github.io/dataganger/reference/detect_roles.md)
  : Detect data roles for each column
- [`suggest_min_rows()`](https://lennon-li.github.io/dataganger/reference/suggest_min_rows.md)
  : Suggest a sufficient synthetic row count

## Synthesis Specification

Define how the synthetic data should be generated — purpose, fidelity,
row count, engine, seed, and disclosure settings.

- [`synth_spec()`](https://lennon-li.github.io/dataganger/reference/synth_spec.md)
  : Create a synthesis specification

## Synthesis

Synthesize a dataset from a real data frame.

- [`synthesize_data()`](https://lennon-li.github.io/dataganger/reference/synthesize_data.md)
  : Synthesize a data double

## Comparison

Compare a synthetic dataset against its original to assess fidelity.

- [`compare_synthetic()`](https://lennon-li.github.io/dataganger/reference/compare_synthetic.md)
  : Compare original and synthetic datasets
- [`plot_comparison()`](https://lennon-li.github.io/dataganger/reference/plot_comparison.md)
  : Plot comparison summaries

## Disclosure and Privacy

Assess and enforce k-anonymity and other disclosure-risk properties.
Synthetic outputs reduce direct disclosure risk but do not provide a
formal privacy guarantee.

- [`privacy_check()`](https://lennon-li.github.io/dataganger/reference/privacy_check.md)
  : Run disclosure-risk privacy checks
- [`assess_kanonymity()`](https://lennon-li.github.io/dataganger/reference/assess_kanonymity.md)
  : Assess k-anonymity over a set of quasi-identifier columns
- [`enforce_kanon()`](https://lennon-li.github.io/dataganger/reference/enforce_kanon.md)
  : Enforce k-anonymity on a synthetic dataset (output guarantee)

## Export and Bundles

Export synthetic data and create agent bundles for sharing with
collaborators or AI programming tools.

- [`export_synthetic()`](https://lennon-li.github.io/dataganger/reference/export_synthetic.md)
  : Export a synthetic data bundle
- [`export_diagnostic_package()`](https://lennon-li.github.io/dataganger/reference/export_diagnostic_package.md)
  : Export a Lens-compatible diagnostic schema for a dataset
- [`make_agent_bundle()`](https://lennon-li.github.io/dataganger/reference/make_agent_bundle.md)
  : Create a one-command agent-ready bundle from a raw data file
- [`check_code_readiness()`](https://lennon-li.github.io/dataganger/reference/check_code_readiness.md)
  : Check whether synthetic data is code-compatible with the original

## Feedback

Report a problem or suggest a feature via a pre-filled GitHub issue.

- [`report_issue()`](https://lennon-li.github.io/dataganger/reference/report_issue.md)
  : Report a problem or share feedback

## CLI

Command-line interface entry point.

- [`dataganger_cli()`](https://lennon-li.github.io/dataganger/reference/dataganger_cli.md)
  : DataGangeR command-line interface

## Shiny App

Launch the interactive DataGangeR Shiny application.

- [`run_app()`](https://lennon-li.github.io/dataganger/reference/run_app.md)
  : Launch the DataGangeR Shiny Application

## Example Datasets

Small synthetic datasets included in the package for use in examples,
tests, and learning the workflow without real data.

- [`example_health_survey`](https://lennon-li.github.io/dataganger/reference/example_health_survey.md)
  : Example health survey dataset
- [`example_admin_claims`](https://lennon-li.github.io/dataganger/reference/example_admin_claims.md)
  : Example administrative claims dataset
- [`example_registry`](https://lennon-li.github.io/dataganger/reference/example_registry.md)
  : Example disease registry dataset
- [`individual_sample`](https://lennon-li.github.io/dataganger/reference/individual_sample.md)
  : Individual-level synthetic sample data
- [`temporal_sample`](https://lennon-li.github.io/dataganger/reference/temporal_sample.md)
  : Temporal synthetic sample data
- [`geographic_sample`](https://lennon-li.github.io/dataganger/reference/geographic_sample.md)
  : Geographic synthetic sample data
