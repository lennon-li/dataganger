## Resubmission

This is version 0.8.1, a focused correction to 0.8.0 in response to the
current CRAN check failures on r-devel-linux-x86_64-fedora-clang,
r-devel-linux-x86_64-fedora-gcc, and the M1 additional check.

## Corrections to the 0.8.0 check failures

The three reports reduce to the same failing test for character-stored
12-hour date/time synthesis. The test expected values ending in `AM` or `PM`,
but reported only a logical FALSE and did not show the generated values.

This was not addressed by relaxing the test. Investigation showed a production
portability defect: `synth_date_like_character()` delegated `%p` rendering to
the host locale. Depending on locale and OS, `%p` can be uppercase, lowercase,
translated, or empty. An empty marker makes a 12-hour timestamp ambiguous and
violates the function's source-format preservation contract.

The formatter now:

- detects ASCII `AM`/`PM` or `am`/`pm` tokens in the source values;
- derives the period from each synthesized hour rather than locale `%p`;
- preserves the source token capitalization;
- leaves non-ASCII locale-native period conventions on the locale-native path.

The regression now reports representative generated values and checks detected
format, successful parsing, source date range, and time-of-day variation. A
contrasting-locale test covers hosts where native `%p` is lowercase or empty.
The same source convention was verified across all 26 locales installed on the
local check host, including uppercase, lowercase, and empty native `%p`
behaviour.

## Generalized portability audit

The package-wide audit also:

- replaced opaque `expect_true(all(grepl(...)))` assertions with diagnostics
  that report offending values;
- removed test source-order dependencies found by a fixed-seed shuffled run;
- removed Unicode multiplication signs in UI labels that generated three
  parser warnings under `LC_ALL=C`, replacing them with portable ASCII `x`;
- added a regression that parses every package R source file under
  `LC_CTYPE=C` without warnings;
- verified source `AM`/`PM` and `am`/`pm` round trips under all 26 installed
  locales;
- verified date/time behaviour under UTC, America/Toronto, and Asia/Kolkata;
- verified identical synthesized values in three fresh R processes;
- rebuilt and exercised the complete bundle from a read-only installed package
  without modifying the installed tree.

## Test environments

- Local Ubuntu 24.04, R 4.6.1, default UTF-8 locale
- Local Ubuntu 24.04, R 4.6.1, `LC_ALL=C`, `TZ=UTC`
- Local R 4.6.1, package installed into a read-only temporary library
- 26 installed `LC_TIME` locales, including locales with uppercase, lowercase,
  and empty native `%p`
- Timezones UTC, America/Toronto, and Asia/Kolkata

External CI/platform results for the exact 0.8.1 commit will be reconciled
before submission.

## R CMD check results

0 errors | 0 warnings | 1 note

The NOTE is the CRAN incoming feasibility message:

```
Days since last update: 1
```

Version 0.8.1 is a focused corrective release submitted immediately after
0.8.0 because the locale-dependent failures described above appeared on the
CRAN check services.

The final source tarball was checked with `R CMD check --as-cran`, including
installed tests, examples, vignettes, rebuilt vignette outputs, and PDF/HTML
manuals.

The dependency-complete source suite reported 0 failures, 51 expected
privacy/enforcement warnings, 9 audited environment/absent-dependency skips,
and 2289 passes. The installed CRAN-mode suite reported 0 failures, 51 expected
warnings, 12 audited CRAN/installed-environment skips, and 2244 passes.

## Downstream dependencies

There are no downstream dependencies.
