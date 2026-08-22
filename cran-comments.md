## Resubmission

This is version 0.8.1, a focused correction to 0.8.0 in response to the
current CRAN check failures on r-devel-linux-x86_64-fedora-clang,
r-devel-linux-x86_64-fedora-gcc, and the M1 additional check.

## Corrections to the 0.8.0 check failures

The reports reduce to the same failing test for character-stored 12-hour
date/time synthesis. The test expected values ending in `AM` or `PM`, but
reported only a logical FALSE and did not show the generated values.

This was not addressed by relaxing the test. Investigation confirmed the
portability defect noted in the CRAN correspondence: `AM`/`PM` is locale- and
OS-dependent, and the package delegated `%p` to the C library in both
directions.

- Parsing: `detect_date_format()` fed `%p` to `strptime()` and measured
  round-trip fidelity with `format()`. Where the locale defines no period
  marker, the 12-hour candidate format neither parses nor round-trips, so a
  column such as `"01/01/2020 01:15 PM"` was misdetected as a 24-hour format.
  Both the marker and the morning/afternoon distinction were lost.
- Formatting: `synth_date_like_character()` rendered `%p` through the locale,
  which can be uppercase, lowercase, translated, or empty. An empty marker
  makes a 12-hour timestamp ambiguous and violates the function's
  source-format preservation contract.

The fix removes the platform from the path entirely. `%p` is no longer passed
to `strptime()` or `format()` at all. Dedicated helpers now:

- read the trailing ASCII `AM`/`PM` token from each source value and apply the
  12-hour to 24-hour hour correction directly, so detection and parsing of a
  12-hour column give the same result on every platform and locale;
- treat a value with no period marker as not matching a 12-hour format, as a
  strict `strptime()` would;
- derive the output period from each synthesized hour, and write it using the
  source column's own convention (`AM`/`PM` or `am`/`pm`).

24-hour and date-only formats are unaffected.

## Regression coverage

The previous regression could only fail on a host whose installed locales
include one with a non-uppercase or empty `%p`, which is why it passed
locally and failed on the CRAN check services. The new coverage does not
depend on the host's installed locales:

- a structural guard that traces `base::strptime()` and `base::format.POSIXct()`
  during a full synthesis run and fails if either is ever given a format
  containing `%p`;
- direct assertions on detection, parsing, and the 12 AM / 12 PM boundaries,
  including that a value with no marker does not parse as 12-hour and that a
  24-hour column is still detected as 24-hour;
- marker-case preservation for a lowercase `am`/`pm` source column;
- the earlier contrasting-locale test, retained, which skips where no such
  locale is installed.

Assertions that previously reported an opaque `expect_true(all(grepl(...)))`
FALSE now report representative generated values.

## Also in this release

- Unicode multiplication signs in UI sample labels were replaced with ASCII
  `x` (they produced parser warnings under `LC_ALL=C`), with a regression that
  parses every package R source file under `LC_CTYPE=C`.
- Test-file setup was isolated to remove source-order dependence found by a
  fixed-seed shuffled run.

## Test environments

- Local Ubuntu 24.04 (WSL2), R 4.6.1, `R CMD check --as-cran`
- GitHub Actions: ubuntu-latest (r-devel, release, oldrel-1), macOS-latest
  (release), windows-latest (release)

The macOS release runner is the environment that reproduced this failure
class (`LC_TIME=en_GB`, empty `%p`).

## R CMD check results

0 errors | 0 warnings | 1 note

The NOTE is the CRAN incoming feasibility message:

```
Days since last update: 1
```

Version 0.8.1 is a focused corrective release submitted immediately after
0.8.0 because the locale-dependent failure described above appeared on the
CRAN check services.

The installed CRAN-mode test suite reported 0 failures, 51 expected
privacy/enforcement warnings, 13 environment-dependent skips, and 2250 passes.

## Downstream dependencies

There are no downstream dependencies.
