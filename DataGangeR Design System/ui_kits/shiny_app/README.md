# UI Kit · Shiny App

A high-fidelity recreation of the DataGangeR Shiny app — the package's web UI. Six-step workflow: upload → profile → roles → spec → synthesise → compare.

## Files

| File | What it is |
| --- | --- |
| `index.html` | App shell, mount + boot. |
| `shiny-app.css` | App-level styles (composes tokens from `colors_and_type.css`). |
| `Components.jsx` | Primitives: `Sidebar`, `Card`, `Banner`, `Chip`, `Btn`, `Seg`, `DoubleRule`, `Histo`, `RoleTag`. |
| `UploadScreen.jsx` | Step 01 — drop zone + recent files. |
| `ProfileScreen.jsx` | Step 02 — the signature column-by-column profile table. |
| `App.jsx` | App shell with `RolesScreen`, `SynthesiseScreen`, click-through nav, floating action bar. |
| `SpecScreen.jsx` | Step 04 — purpose picker + level + spec preview as console block. |
| `CompareScreen.jsx` | Step 06 — side-by-side original/synthetic + comparison table + export. |

## Interactions modelled

- Click any step in the left rail to jump to it.
- Bottom-right ↻ next button advances through the workflow.
- Purpose radios in step 04 update the spec preview live.
- The Compare screen's "Download bundle" is mocked with an alert.

## Layout pattern

`296px` sidebar + flexible main column. The floating action bar at the bottom of the main column is the only thing using `backdrop-filter` — keep it that way.

## Component scope

Cosmetic only. No real data flow, no real synthesis. The point is the surface and the patterns, not the engine.
