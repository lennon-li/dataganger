## Test environments

- GitHub Actions ubuntu-latest, R release
- GitHub Actions ubuntu-latest, R devel
- GitHub Actions macos-latest, R release
- GitHub Actions windows-latest, R release
- Local R 4.6.0 x86_64-pc-linux-gnu (Ubuntu 24.04, WSL2)

## R CMD check results

0 errors | 0 warnings | 1 note

**Note 1 — New submission:**

    checking CRAN incoming feasibility ... NOTE
    Maintainer: 'Lennon Li <yeli@biostats.ai>'
    New submission

This is a new package submission. It is expected and unavoidable.

One additional note appears only under WSL2 network isolation (not on
GitHub Actions or win-builder):

    checking for future file timestamps ... NOTE
    Unable to verify current time.

This is caused by the local machine being unable to reach an NTP host and
does not reflect a package problem.

## Downstream dependencies

This is a new submission. There are no downstream dependencies.
