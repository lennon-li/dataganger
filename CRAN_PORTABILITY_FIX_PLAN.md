# CRAN Portability Correction Plan

Base: `main` at `895b355a24869d85bdb677d515191ef941a4bf86`

## Objective

Correct the remaining locale-dependent date/time behavior and make future CRAN
failures actionable. The release must not classify a value as a date and then
silently resample it as a category, accept a format that changes or discards
source text, or publish a boolean test failure without the values needed to
diagnose it.

The ASCII AM/PM boundary fix in 0.8.2 remains required. This plan closes the
gaps around month names, translated period markers, round-trip validation, test
diagnostics, and CRAN-facing documentation.

## Confirmed Gaps

1. Month-name recognition was broadened in role detection, but parsing still
   depends on the active `LC_TIME`. Under `LC_ALL=C`, non-English month names
   can be classified inconsistently or fall through to categorical synthesis.
2. The private AM/PM path recognizes ASCII `AM` and `PM` only. A translated
   period suffix can be parsed as a 24-hour value, stripping the suffix and
   collapsing distinct morning and afternoon times.
3. `detect_date_format()` can accept a candidate with zero round-trip fidelity.
   A value such as `01/01/2020 01:15 FOO` can therefore lose `FOO` without an
   explicit failure.
4. A substantial number of aggregate `expect_true(all(...))` and
   `expect_true(any(grepl(...)))` assertions still report only `TRUE`/`FALSE`.
5. `NEWS.md` and `cran-comments.md` overstate the breadth of locale support and
   the completeness of the test-diagnostic cleanup. The recorded CRAN flavor
   status is also stale.

## Phase 1: Add Failing Regression Tests

Write the tests before production changes and record the commands that show the
expected failures.

- Add helper-level tests proving that a candidate date format is rejected when
  it cannot round-trip at least 90 percent of the non-missing source values.
- Add full-path tests from `detect_roles()` through synthesis for character
  dates with abbreviated, full, dotted, lowercase, and accented month names.
  Assert the selected role, the date-specific synthesis path, output format,
  parseability, and deterministic seeded behavior. Do not test only the role.
- Run the month-name tests with `LC_ALL=C`. Support only forms the package can
  parse independently of host locale; otherwise fail closed and document the
  unsupported form instead of silently treating it as a generic category.
- Preserve regression coverage for `12 AM`, `12 PM`, case variants, marker
  spacing, and formats with seconds.
- Add translated-period coverage. When native `strptime()` can parse the token
  in the active locale, retain that native path. When the token cannot be
  parsed, reject the format; never reinterpret it as 24-hour time or discard
  the suffix.
- Add a regression fixture with unknown suffixes such as `FOO` and `BAR` to
  prove that zero-fidelity candidates are rejected.
- Every failing assertion must name the offending input, unexpected output, or
  inspected command output.

## Phase 2: Make Parsing Fail Closed

Unify detection and synthesis around the same validated parser.

- Keep the locale-independent ASCII AM/PM conversion for strings that actually
  contain an ASCII period marker.
- For `%p` formats without an ASCII marker, use native locale parsing and
  formatting only when round-trip validation succeeds.
- Require a documented minimum round-trip fidelity of 0.90 before accepting a
  candidate in `detect_date_format()`. A parsed candidate with lower fidelity
  is not a detected format.
- Ensure role detection uses the same parseability decision as synthesis.
  Values that cannot enter the date synthesis path must not be labeled as dates
  solely by a permissive regular expression.
- Never fall back silently from a detected date to categorical resampling.
  Either parse through the validated date path or retain a non-date role with
  an explicit, test-covered reason.
- Preserve format, missingness behavior, range/coarsening controls, seeded
  determinism, and the existing ASCII AM/PM boundary semantics.

This phase must not alter the export bundle, k-anonymity ordering, attestation
gate, no-network guarantee, or any other privacy-critical contract in
`AGENTS.md`.

## Phase 3: Enforce Actionable Test Failures

- Replace opaque `any(grepl(...))` expectations with `expect_match()` or an
  equivalent assertion that includes the inspected output.
- Replace high-risk aggregate range, membership, and format checks with
  expectations that print the offending values. Prioritize synthesis, CLI,
  privacy, export, and manifest tests.
- Add a package-wide static test that parses test files and rejects newly added
  opaque aggregate boolean expectations. The gate must identify the file,
  expression, and line. It may allow an aggregate assertion only when the
  assertion supplies explicit diagnostic context or the tested expression
  itself exposes offending values.
- Do not replace useful semantic assertions with a weaker expectation merely to
  satisfy the static gate.

## Phase 4: Correct Release Documentation

- In `NEWS.md` and `cran-comments.md`, document each observed symptom, root
  cause, code fix, regression test, and verification environment separately.
- Scope locale claims to behavior that the test matrix demonstrates. Do not say
  "any locale" when only ASCII period markers or installed locales are tested.
- State explicitly that unsupported foreign-locale text fails closed rather
  than being silently reinterpreted.
- Describe which aggregate assertions were converted and what static gate now
  prevents regressions. Do not claim that every test is maximally diagnostic
  unless the audit proves it.
- Refresh CRAN flavor information from the current check page immediately
  before submission, or omit volatile per-flavor version claims and link to the
  live status instead.
- Keep version `0.8.2` unless release policy requires another version after the
  code correction. Do not release or submit as part of implementation.

## Phase 5: Independent Verification

Run all gates from a clean worktree after implementation:

```sh
Rscript --vanilla -e 'devtools::test(filter = "detect-roles|synthesize-data")'
LC_ALL=C TZ=UTC Rscript --vanilla -e 'devtools::test(filter = "detect-roles|synthesize-data")'
DATAGANGER_TEST_SYNTHPOP=true Rscript --vanilla -e 'devtools::test()'
LC_ALL=C TZ=UTC DATAGANGER_TEST_SYNTHPOP=true Rscript --vanilla -e 'devtools::test()'
Rscript --vanilla -e 'devtools::check(manual = FALSE, vignettes = FALSE)'
```

Also require:

- zero failures and no unexplained increase in skips in both full test runs;
- a fixed-seed shuffled test run to expose order dependence;
- targeted tests in every installed non-C `LC_TIME` available on the host;
- `R CMD check --as-cran` on the built source tarball with zero errors and zero
  warnings;
- ASCII checks for `R/`, `man/`, `DESCRIPTION`, `NAMESPACE`, and tests;
- URL, spelling, and no-network checks already used by CI;
- a read-only smoke test against the installed tarball.

## Completion Criteria

Implementation is complete only when all regression tests fail before the fix,
pass after it, and the independent verification is green. The final review must
inspect the actual diff, verify that documentation matches demonstrated
behavior, enumerate residual skips, and reject any unsupported readiness claim.

Implementation must not create a branch, commit, push, open a PR, deploy,
release, or submit to CRAN. Those actions require separate owner authorization.
