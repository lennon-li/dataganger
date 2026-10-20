# DataGangeR threat model for Anthropic OSS Scanner

## Purpose and trust boundaries
DataGangeR is an R package and Shiny application for producing synthetic stand-ins from potentially sensitive source datasets. Source data, fitted frozen generators, approval records and generated bundles may carry privacy risk. Synthetic output is not guaranteed anonymous.

## Untrusted entry points
- Uploaded CSV, Excel and SAS datasets and their filenames, column names, values and metadata.
- CLI arguments, recipe YAML, bundle archives and manifests.
- Shiny input, file upload and export parameters.
- Paths to frozen-generator stores, approval records and output bundles.

## Security invariants
- Original records must not be transmitted to remote services without explicit authorization.
- Human review and approval boundaries must not be bypassed by crafted input, forged receipts or manipulated metadata.
- A generate-only Agent route must not expose raw input or fitted generator state.
- Untrusted paths and archives must not allow traversal, arbitrary overwrite, unsafe deserialization or execution.
- Secrets and sensitive records must not leak to logs, errors, generated artifacts or reports.
- Revoked or destroyed generators must not remain usable through stale approvals.

## Severity guidance
Critical: practical unauthenticated exfiltration of raw data or secrets, arbitrary code execution in a normal package workflow, or broad bypass of authorization boundaries.
High: exploitable approval bypass, unauthorized access to generator state, meaningful data disclosure, or arbitrary file write/read under typical deployment.
Medium: narrower information leakage, denial of service, or vulnerabilities requiring significant preconditions.
Low: defense-in-depth issues with limited demonstrated impact.
Rate vulnerabilities on demonstrated reachability and impact, not hypothetical model behavior.

## Scanner guidance
Use synthetic fixtures only. Never include private patient records or real credentials in reproductions. Provide the affected file/function, exact prerequisites, minimal safe reproduction, impact, and a focused patch with regression tests. Avoid broad refactors. Verify findings against the current code and existing privacy controls.
