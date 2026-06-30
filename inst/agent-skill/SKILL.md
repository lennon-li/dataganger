You are not allowed to read the original data.

# DataGangeR agent workflow

Use DataGangeR to work only from synthetic data generated from the user's real dataset. Never open, preview, sample, parse, or inspect the real data file directly. Generate synthetic data only by calling the package or CLI with the user's chosen UI settings:

- `spec.yaml`
- `roles.yaml`
- seed from the exported spec

Treat the real data file as an opaque input to DataGangeR.

## First step: reproduce the UI output exactly

Before doing any analysis or coding work, run:

```sh
dataganger synthesize <real-data> --spec spec.yaml --roles roles.yaml --out check.zip
```

Then extract the synthetic CSV from `check.zip` and confirm it is identical to the UI-generated `synthetic_data.csv` already in the folder. For example:

```sh
unzip -p check.zip synthetic_data.csv > check_synthetic_data.csv
cmp -s check_synthetic_data.csv synthetic_data.csv
diff -u synthetic_data.csv check_synthetic_data.csv
```

Proceed only if the files are identical. If they differ, stop and report that reproduction failed.

## Column names and schema

Column names may vary because the name strategy may rename them. Never assume original column names. Read the names and meanings from `data_dictionary.csv`, and use the synthetic column names recorded there.

## Allowed workflow

1. Reproduce the synthetic output exactly with the command above.
2. Work from `synthetic_data.csv`, `data_dictionary.csv`, `README.md`, `ai-readme.md`, `privacy_report.txt`, and other exported bundle files.
3. Inspect the synthetic data, profile it, write code against it, and propose transformations using only the synthetic bundle.
4. If the user wants variations, ask DataGangeR to generate them by changing `n`, seed, or other user-approved settings in `spec.yaml`, then synthesize again.

## Never do this

- Do not read the original data into R, Python, SQL, spreadsheets, or any other tool.
- Do not open the original CSV, Excel, SAS, or other source file for inspection.
- Do not infer that a synthetic column name matches an original name unless `data_dictionary.csv` says so.
- Do not claim the output is risk-free or anonymous.

## Framing

This workflow reduces direct disclosure risk by keeping the agent on synthetic data and reproducible bundle artifacts, but it is not a guarantee of privacy or anonymity. Users still need to review fidelity, privacy warnings, and sharing context before external release.
