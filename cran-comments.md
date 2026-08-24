## Resubmission

Version 0.8.2 corrects locale-sensitive character date/time handling and the
test diagnostics needed to investigate platform-specific failures.

This resubmission answers the maintainer notice giving a 2026-09-05 deadline
to correct the problems shown on the package check page.

## 1. Character-stored 12-hour times

**Symptom.** On hosts where C-library `%p` behavior differed, an ASCII value
such as `"01/01/2020 01:15 PM"` could lose its suffix and afternoon meaning.

**Cause.** Detection and output delegated `%p` to locale- and OS-dependent C
library parsing and formatting, then allowed a lenient 24-hour candidate to
accept text it did not preserve.

**Fix.** ASCII `AM`/`PM` is parsed and rendered in R, including the `12 AM` and
`12 PM` boundaries and marker case. A `%p` candidate with non-ASCII native
markers uses the active locale only when at least 90 percent of non-missing
values parse and round trip after surrounding whitespace is trimmed. Unknown
or mixed suffixes are rejected; they are not stripped or reinterpreted as
24-hour time.

**Regression evidence.** Tests cover ASCII boundaries and variants, trace the
ASCII full-synthesis path to prevent `%p` delegation, reject `FOO`/`BAR` and
C-locale translated suffixes, and exercise native non-ASCII markers when the
active host locale provides them.

## 2. Month names and role/parser agreement

**Symptom.** Role detection could label locale-shaped month text as a date even
when synthesis could not parse it, after which the marginal engine silently
resampled the source strings as categories.

**Cause.** Role detection used a permissive regular expression while synthesis
used a separate locale-bound parser. `detect_date_format()` also accepted the
best parsed candidate even when it reproduced none of the source text.

**Fix.** Role detection and synthesis now share the same format detector. A
candidate requires at least 0.90 round-trip fidelity across trimmed non-missing
values, and a date role without a validated parser errors instead of falling
through. English abbreviated, full, dotted, and lowercase month forms have an
explicit locale-independent parser and renderer.

**Regression evidence and limitation.** Under `LC_ALL=C TZ=UTC`, end-to-end
tests assert role, date-path parsing, output format, reparsing, and same-seed
determinism for `Jan`, `January`, `Jan.`, and lowercase English forms. Accented
and other foreign-locale month text is accepted only when the active locale
parses and formats the candidate with the required fidelity. Otherwise it
fails closed as non-date text. Universal foreign-locale parsing is not claimed.

## 3. Actionable test failures

**Symptom and cause.** Aggregate boolean expectations hid the inspected values,
leaving remote logs with only `FALSE` versus `TRUE`.

**Fix.** All package test uses of opaque `any(grepl(...))` were replaced with
matching expectations that print the inspected output. Every remaining
aggregate `expect_true()`/`expect_false()` supplies diagnostic context that
identifies the inspected or offending values. An AST-based package-wide gate
reports file, line, and expression and rejects any aggregate boolean
expectation without that context. A deliberately bad fixture self-tests that
diagnostic.

## Verification environment

- Ubuntu 24.04.4 LTS, x86_64, R 4.6.1
- Default `LC_TIME=C.UTF-8`
- Portability matrix: `LC_ALL=C TZ=UTC`

Verification on the release tree:

- `DATAGANGER_TEST_SYNTHPOP=true devtools::test()`: 0 failures, 2,341
  passes, 10 audited skips.
- The same complete suite under `LC_ALL=C TZ=UTC`: 0 failures, 2,341
  passes, the same 10 audited skips.
- Fixed-seed shuffled-order suite with synthpop enabled: 0 failures, 2,341
  passes, the same 10 audited skips.
- `devtools::check(manual = FALSE, vignettes = FALSE)`: 0 errors,
  0 warnings, 0 notes.
- Built source tarball, literal `R CMD check --as-cran`: 0 errors,
  0 warnings, 1 incoming-feasibility note (`Days since last update`).
  Vignettes and PDF/HTML manuals were built and checked.
- Full ASCII scan, package spelling, URL checks, and the no-network test
  context: passed.
- ASCII AM/PM synthesis, portable English month parsing, and unknown-suffix
  rejection: passed in all 23 non-C `LC_TIME` locales installed on the
  verification host, including the `en_GB` setting named in the maintainer
  notice. Those 23 are all English regional variants, so they exercise
  regional date and period-marker conventions rather than translated month
  names. Non-English month text is covered by the fail-closed behavior in
  section 2, not by this sweep.
- The checked installed package tree was made read-only; `dataganger
  synthesize` exited 0 from a writable directory and wrote the complete export
  bundle, including `human/comparison_report.html`.

The 10 development-suite skips are environment branches: one unavailable
non-ASCII native-period locale, two installed-package-only subprocess/UI tests,
two optional-package presence/absence branches, four tests whose absent-
`synthpop` branch is inapplicable because synthpop is installed, and one SAS
labelling limitation. The installed-package check exercises the installed
paths.

The live CRAN check page was reviewed at its 2026-08-24 15:51 CEST update:
<https://cran.r-project.org/web/checks/check_results_dataganger.html>. Every
0.8.0 failure there is the same single assertion,
`test-synthesize-data.R:782` ("character-stored date+time strings preserve
both the date range and the time-of-day format"), reporting
`FAIL 1 | WARN 51 | SKIP 11 | PASS 2240` on r-devel-linux-x86_64-fedora-clang,
r-devel-linux-x86_64-fedora-gcc, and the M1mac additional check. That is the
ASCII AM/PM defect addressed above. Flavors still carrying an older version
are not enumerated here because that status is volatile.

## Downstream dependencies

There are no downstream dependencies.
