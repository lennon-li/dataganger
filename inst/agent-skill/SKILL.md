You are not allowed to read the original data.

# DataGangeR agent workflow

Use DataGangeR to work only from synthetic data generated from the user's real dataset. The real data and its path stay with the trusted human or operator. Never request, receive, open, preview, sample, parse, inspect, or pass that path to DataGangeR.

## First step: read the bundle metadata

Read `manifest.json` and `../human/human.md` before working with the synthetic
data. `recipe.yaml` records the synthesis configuration: settings, per-column
roles, and seed. It is not a fitted generator and cannot regenerate data by
itself.

Reruns *from the original data* require that data and must be performed by a
trusted human or operator, not by you.

A **frozen generator** is different. Once a human has frozen and approved a
generator, further variations can be produced from the fitted state alone, with
no access to the original data. If the operator gives you a store path and an
approved contract ID, you may generate additional variations yourself -- see
"Generating more data from an approved contract" below. Without one, ask the
human to generate and review a bundle, then provide it.

## Files you may use

Work only from these bundle artifacts:

- `recipe.yaml`
- `manifest.json`
- `code_readiness_report.json` (may be absent)
- `../human/human.md`
- `../synthetic_data.csv`

Do not assume other files exist.

Hard rule: Before using the data, read `manifest.json`. If `blockers` is non-empty, STOP and tell the user; do not analyse or build on the data until a human regenerates or acknowledges.

## Column names and schema

Column names may vary because the name strategy may rename them. Never assume original column names. Read the names and mappings from `recipe.yaml`'s `name_map` when present, and use `../human/human.md` for the treatment list describing how each output column was handled.

## Allowed workflow

1. Work only from `../synthetic_data.csv` and the listed bundle metadata files.
2. Inspect the synthetic data, profile it, write code against it, and propose transformations using only the synthetic bundle.
3. If `code_readiness_report.json` is present, use it to catch structural mismatches that would break code on the original data.
4. If the user wants variations and an approved frozen contract is available,
   generate them yourself from that contract (see below). Otherwise ask a
   trusted human or operator to generate and review a new bundle. Do not
   modify `recipe.yaml`.

## Never do this

- Do not read the original data into R, Python, SQL, spreadsheets, or any other tool.
- Do not open the original CSV, Excel, SAS, or other source file for inspection.
- Do not run DataGangeR synthesis commands with a real-data path.
- Do not modify `recipe.yaml` to request reruns or variations.
- Do not run `generator freeze`, `generator revoke`, or `generator destroy`, and do not approve a generator. Those are human operator actions; `revoke` and `destroy` are irreversible.
- Do not pass `--acknowledge-kanon` or `--acknowledge-exact-match`. A flagged generation needs a human decision.
- Do not open, copy, or inspect files inside a private generator store directly; use the documented commands.
- Do not infer that a synthetic column name matches an original name unless `recipe.yaml` or `../human/human.md` supports it.
- Do not claim the output is risk-free or anonymous.

## Framing

This workflow reduces direct disclosure risk by keeping the agent on synthetic data and reproducible bundle artifacts, but it is not a guarantee of privacy or anonymity. Users still need to review fidelity, privacy warnings, and sharing context before external release.

## Generating more data from an approved contract

Once a human has frozen and approved a generator, generation no longer needs
the original data -- it runs from the fitted state in a private store. If the
operator gives you a store path and an approved contract ID, generate directly:

```
dataganger generator generate --store <dir> --contract-id <id> --out bundle.zip \
  [--seed <int>] [--n <rows>] [--datasets <k>]
```

The human who approved the contract set the permitted seed, row-count, and
dataset-count ranges. Requests outside those bounds are refused.

The same privacy machinery runs on your request as on a human's, and it fails
closed: k-anonymity enforcement, the keyed exact-row check, and the standard
blockers all apply. If a generation is flagged, the bundle is not written
unless the corresponding acknowledgement flag is passed -- do not pass those
flags yourself; report the flag to the operator and let a human decide.

Read `manifest.json` in the resulting bundle first, exactly as with any other
bundle, and stop if `blockers` is non-empty.

### Stay generate-only

Use `generator generate`, `generator inspect`, and `generator status` only.
Freezing, approval, revocation, and destruction are human operator actions:
`revoke` and `destroy` are irreversible and `destroy` removes fitted state for
every generator under the contract. Do not run them, and do not work around a
refusal by opening files in the store directly.

Note honestly what this is: with a store path you are inside the operator's
trust boundary, so the generate-only restriction above is **policy you follow,
not a boundary enforced against you**. Treat it as binding anyway.

### Optional hardened host route

Some hosts additionally run a two-process broker so the calling account has no
read access to the store at all, and the generate-only restriction becomes
OS-enforced rather than advisory:

```
dataganger agent status   --contract-id <id>
dataganger agent generate --contract-id <id> --out bundle.zip [--n <rows>] [--datasets <k>] [--seed <int>]
```

This route takes a contract ID and bounded request fields only -- no store
path, no data path, no privacy acknowledgement or opt-out. Use it when the
operator points you at it. If `status` reports `unavailable`, the host has not
configured it; fall back to the store route above if the operator provided one,
and never try to reach the private store another way.

The availability check proves that the answering process runs as a different OS
principal, is not a superuser, and was genuinely refused when it tried to read
the store. It does not prove the host is correctly configured in any other
respect, and it is not a privacy guarantee.
