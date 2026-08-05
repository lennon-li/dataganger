# Security and provenance

DataGangeR is designed to reduce direct disclosure risk when preparing synthetic
stand-ins for real data. It does not guarantee privacy; review the package's privacy
warnings and every output before external sharing.

## Official distributions

Use only the following official sources:

- Released package: CRAN (`install.packages("dataganger")`).
- Development source and release tags: <https://github.com/lennon-li/dataganger>.
- Documentation: <https://dataganger.biostats.ai/>.

Forks, mirrors, and repackaged copies are independently maintained. They are not
reviewed, released, or endorsed by DataGangeR. Do not assume that their privacy
behavior, dependencies, or build artifacts match an official release. For a GitHub
development installation, verify the `lennon-li/dataganger` owner and the exact
commit or release tag before use.

## Reporting a security or privacy concern

Do not open a public issue with real data, synthetic output derived from sensitive
data, credentials, or reproduction steps that expose private information.

For a potential vulnerability or privacy-control failure in an official release,
contact the maintainer privately at <yeli@biostats.ai>. Include the package version,
a minimal non-sensitive reproduction, impact, and any proposed mitigation. Do not
expect a response-time commitment from this file.

For ordinary bugs, usability feedback, and feature requests that contain no sensitive
material, use the canonical repository's issue tracker.
