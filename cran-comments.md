## Test environments

- GitHub Actions ubuntu-latest, R release
- GitHub Actions ubuntu-latest, R devel
- GitHub Actions macos-latest, R release
- GitHub Actions windows-latest, R release
- Local R 4.6.0 x86_64-pc-linux-gnu (Ubuntu 24.04, WSL2)

## R CMD check results

0 errors | 0 warnings | 0 notes

One environment-only note appears under WSL2 network isolation:

    checking for future file timestamps ... NOTE
    Unable to verify current time.  To disable remote verification,
    set environment variable _R_CHECK_SYSTEM_CLOCK_ to a false value.

This note does not appear in connected environments (GitHub Actions, win-builder).
It is caused by the local machine being unable to reach an NTP host, not by the
package itself.

## Downstream dependencies

This is a new submission. There are no downstream dependencies.
