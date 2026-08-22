## Resubmission

This is version 0.8.2, a portability correction to 0.8.0 in response to the
current CRAN check failures on r-devel-linux-x86_64-fedora-clang,
r-devel-linux-x86_64-fedora-gcc, and the M1mac additional check, and to the
maintainer notice observing that `AM`/`PM` are locale- and OS-dependent.

Version 0.8.1 was prepared for this purpose but never submitted; it corrected
only half of the defect. Everything in it is included here.

## 1. The reported failure: character-stored 12-hour date/time synthesis

The three reports reduce to one test. It expected synthesized values to end in
`AM` or `PM`, and reported only a logical FALSE.

**Cause.** `%p` is handed to the C library by both `strptime()` and
`format()`, and is locale- and OS-dependent: it can be uppercase, lowercase,
translated, or empty. The package used it in both directions.

- Detection and parsing. `detect_date_format()` fed `%p` to `strptime()` and
  measured round-trip fidelity with `format()`. Where the locale defines no
  period marker, the 12-hour candidate neither parses nor round-trips, so a
  column such as `"01/01/2020 01:15 PM"` was misdetected as 24-hour. Both the
  marker and the morning/afternoon distinction were lost, and every PM value
  collapsed onto its AM hour.
- Formatting. `synth_date_like_character()` rendered `%p` through the locale.
  An empty marker makes a 12-hour timestamp ambiguous and violates the
  function's source-format preservation contract.

**Fix.** `%p` is no longer passed to `strptime()` or `format()` at all.
Dedicated helpers read the trailing ASCII `AM`/`PM` token from each value and
apply the 12-to-24 hour correction directly, treat a value with no marker as
not matching a 12-hour format (as a strict `strptime()` would), and derive the
output period from each synthesized hour, written in the source column's own
case convention. 24-hour and date-only formats are untouched.

**Verification.** A structural regression traces `base::strptime()` and
`base::format.POSIXct()` through a full synthesis run and fails if either is
ever handed a format containing `%p`. It was confirmed to fail when the old
formatter is reintroduced. This does not depend on which locales the check
host has installed, which is why the previous regression passed locally and
failed on the CRAN services.

## 2. The same defect class elsewhere: month-name dates

Acting on the maintainer's general point, the audit found the same
locale-dependence in date detection. `detect_roles()` matched a month-name
column with `[A-Z][a-z]{2}`, an English-style capitalized three-letter
abbreviation. Month names come from the host locale, so a column written with
lowercase, dotted, accented, or longer month names went undetected and fell
through to categorical resampling. The pattern now accepts those forms, and
the regression asserts on literal strings rather than `format()` output so it
holds on every host.

## 3. Diagnosability

The original report was unactionable because the assertion printed no values.
The remaining opaque `expect_true(all(...))` assertions now name the offending
values, and the 12-hour regressions report representative generated values,
along with boundary assertions for `12 AM`/`12 PM` and marker-case
preservation. This raises the testthat requirement to `>= 3.2.0` for
`expect_in()`.

## 4. The flavors still reporting 0.6.1

r-devel-debian (clang and gcc), r-patched-linux and r-release-linux still show
0.6.1. Those failures are in `test-cli-execution.R` and came from `knitr`
writing intermediate files into the installed package directory, which is
read-only on those hosts. That was corrected in 0.8.0, where
`rmarkdown::render()` is called with `intermediates_dir = tempdir()`.

Because those flavors have not yet checked 0.8.x, the correction was
re-verified for this submission: the package was installed into a temporary
library, the installed tree was made read-only (`chmod -R a-w`), and
`dataganger synthesize` was run from a writable working directory with a
relative `--out` path. It exited 0 and wrote the complete bundle, including
the rendered `human/comparison_report.html`.

## Also in this release

- Unicode multiplication signs in sample labels produced parser warnings under
  `LC_ALL=C`; they are now ASCII `x`, with a regression that parses every
  package R source file under `LC_CTYPE=C`.
- Test-file setup was isolated, removing a source-order dependence found by a
  fixed-seed shuffled run.

## Test environments

- Local Ubuntu 24.04 (WSL2), R 4.6.1, `R CMD check --as-cran`
- Local, package installed into a read-only temporary library
- GitHub Actions: ubuntu-latest (r-devel, release, oldrel-1; plus no-network
  and synthpop-enabled variants), macOS-latest (release), windows-latest
  (release)

The macOS release runner reproduces the reported failure class
(`LC_TIME=en_GB`, empty `%p`) and is green on the release commit.

## R CMD check results

0 errors | 0 warnings | 1 note

The NOTE is the CRAN incoming feasibility message:

```
Days since last update: 1
```

0.8.2 is a corrective release submitted immediately after 0.8.0 because the
locale-dependent failures described above appeared on the CRAN check services.

## Downstream dependencies

There are no downstream dependencies.
