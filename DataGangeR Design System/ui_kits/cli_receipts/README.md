# UI Kit · CLI Receipts

The R console is DataGangeR's other UI. Every package function that returns a structured object also defines a `print.*` method that emits a **receipt** — a coloured, sectioned printout that's the user's first read of the result.

These receipts are the canonical templates. Match the structure, dividers, and colour cues when extending.

## What's here

- `index.html` — visual mockup of the receipts as the user sees them. Open in a browser.

## Receipts modelled

| R function | print method | Receipt |
| --- | --- | --- |
| `profile_data()` | `print.dataganger_profile` | Column types, missingness, per-column details. |
| `synth_spec()` | `print.dataganger_spec` | Purpose, level, key settings, seed. |
| `privacy_check()` | `print.dataganger_privacy_check` | Flags table, severity, hardening applied. |
| `compare_synthetic()` | `print.dataganger_comparison` | Per-variable std_diff and TVD. |
| `export_synthetic()` | stream of `cli::cli_alert_*` | "→ done · (0.4s)" progress lines. |

## Structure rules

1. **Headline rule.** Every receipt opens with `── DataGangeR <Thing> ─────` (em-dash rule, brand-cased noun).
2. **Section H2.** `── Section ─────` in `--real-300` (green) — used for groupings.
3. **Section H3.** Bare label in white — used for per-item blocks.
4. **Bullets.** `•` at start, single space.
5. **Values.** `--real-300` (green) for the value side of a key/value pair.
6. **Keys.** `--synth-300` (magenta) for the key side.
7. **Warnings.** Prefix `!` in `--risk-300` (orange). One sentence.
8. **OK / done.** Prefix `✓` or `→` in `--real-300`.
9. **Footnote.** `i ` prefix in `--paper-400` (dim) for advisory info.

## Colour mapping in console

`cli` colour roles map to:

- `cli::cli_h1` → bold white
- `cli::cli_h2` → real green
- `cli::cli_alert_warning` → risk orange
- `cli::cli_alert_success` → real green
- value spans (`{.val ...}`) → real green
- code spans (`{.code ...}`, `{.arg ...}`) → synth magenta
