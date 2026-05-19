---
name: dataganger-design
description: Use this skill to generate well-branded interfaces and assets for DataGangeR, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping the R package's Shiny app and CLI receipts.
user-invocable: true
---

# DataGangeR design skill

DataGangeR generates synthetic data doubles from real datasets — for biostatisticians, R/Shiny developers, and analysts who need to hand a dataset to a teammate, a student, or an AI assistant without handing over real records. This skill contains everything you need to design for it.

## Start here

Read **`README.md`** for the brand at a glance, content fundamentals (tone, voice, casing, "no overclaims"), visual foundations (the real/synth pair, paper-and-ink base, the "doubled but not identical" motif), and iconography. Then explore:

- **`colors_and_type.css`** — color tokens, type scale, spacing, radii, shadows, the `--shine` specular. Link this from every artefact.
- **`assets/`** — `logomark.svg` (R with ghost trail + data rows), `wordmark.svg` ("gangeR"), `lockup.svg`, `double-mark.svg` (multi-exposure illustration).
- **`ui_kits/shiny_app/`** — JSX components and a click-through prototype of the Shiny app. Lift `Sidebar`, `Card`, `Banner`, `Chip`, `Btn`, `Seg`, `DoubleRule` for new screens.
- **`ui_kits/cli_receipts/`** — the R-console printout patterns. Match these for any console output.
- **`preview/`** — small one-card specimens for every token group. Useful as a visual reference.

## When asked to build something

If creating **visual artifacts** (slides, mocks, throwaway prototypes), copy the assets out of `assets/` and create a static HTML file that links `colors_and_type.css`. Use the `t-*` recipe classes (`t-display`, `t-eyebrow`, `t-mono`, etc.) and the semantic CSS vars (`--bg`, `--fg`, `--accent`, `--real`).

If working on **production code** (the actual R/Shiny app), copy assets and read the rules in `README.md` to become an expert in designing with this brand.

If invoked **without other guidance**, ask the user what they want to build, ask a couple of clarifying questions (which surface? which step of the workflow? real or mocked data?), and then act as an expert designer producing HTML artifacts or code as needed.

## The non-negotiables

- **The real/synth pair is everything.** Anywhere original data and synthetic data appear together, they go side-by-side with `--real-500` (lichen green) on the left and `--synth-500` (magenta) on the right.
- **Privacy uses burnt orange (`--risk-500`), never red.** Status red exists but is reserved for destructive UI.
- **No emoji. No gradient backgrounds.** The product is a data tool.
- **One controlled gloss** — the `--shine` shadow on the primary CTA and the wordmark mark. Nowhere else.
- **Mono for data.** Every variable name, value, code span, and CLI receipt is JetBrains Mono.
- **"No overclaims."** When writing copy about privacy, hedge. "Reduces direct disclosure risk", "not a substitute for", "review the comparison report".
