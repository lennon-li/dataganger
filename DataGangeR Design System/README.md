# DataGangeR — Design System

> Synthetic Data Doubles for Safer Prototyping.
> _DataGangeR_ creates **doppelgängers** of real datasets so analysts can prototype, teach, and collaborate with AI without sharing original records.

This folder is the design system that supports the package, its CLI receipts, and the Shiny web UI. Use it whenever you're producing screens, slides, docs, or marketing for DataGangeR.

---

## Index

| File / folder | What it is |
| --- | --- |
| `colors_and_type.css` | Color tokens, type scale, spacing, radii, shadows. |
| `fonts/` | _(empty — using Google Fonts substitutes; see Caveats)_ |
| `assets/` | Logo lockups, brand marks, icons, illustration. |
| `preview/` | Self-contained HTML cards that populate the Design System tab. |
| `ui_kits/shiny_app/` | High-fidelity recreation of the DataGangeR Shiny app. |
| `ui_kits/cli_receipts/` | The CLI / R-console "receipts" used in the package output. |
| `SKILL.md` | Agent-skill entrypoint — read this if you're an AI consuming the system. |

---

## Sources

This system was built from the public source for the package:

- **GitHub:** [`lennon-li/dataganger`](https://github.com/lennon-li/dataganger) — package source, R functions, Shiny app scaffold (`R/run-app.R`), CLI print methods (`R/synth-spec.R`, `R/profile-data.R`), and the user-facing README. **Explore this repo to do a better job designing for DataGangeR.**
- **Referenced but not available:** `phase-5-shiny-brief-ming.md` — the user mentioned this brief but it isn't present on the default branch of the public repo. The visual direction here is inferred from the package surface (CLI receipts, function presets, the existing README copy). _Re-attach the brief and I'll align._

---

## Brand at a glance

**Name:** DataGange**R** (the `R` is always treated as a wink to the R language and given the magenta accent). The wordmark uses a simplified **gangeR** lockup; the full name appears in body copy and the package surface.
**Tagline:** _Synthetic data doubles for safer prototyping._
**One-liner:** _Profile your data, dial in a synthesis spec, and walk away with a doppelgänger you can share._
**Audience:** Biostatisticians, clinical/epi researchers, R/Shiny developers, data-science instructors, anyone who needs to hand a dataset to a teammate, a student, or an AI assistant without handing over real records.
**Personality:** Quietly competent. Slightly literary. Honest about limits. A little bit of wit in the name and a single magenta accent — never goofy, never bombastic.

The product has two faces:

1. **The R package** — code-first. Lives in the console. UI surface is the printed object (`print.dataganger_spec`, `print.dataganger_profile`) — clean CLI receipts with headings, bullets, and a single status-color accent.
2. **The Shiny app** — a polished web UI for the same workflow. Six steps: _Upload → Profile → Roles → Spec → Synthesise → Compare → Export._

---

## CONTENT FUNDAMENTALS

### Tone

Three rules:

1. **Honest before clever.** The package README literally says _"No overclaims."_ That's the voice. Never claim the synthetic data is "safe" or "private" — say it _reduces direct disclosure risk_ and point the reader to the comparison report.
2. **Technical but kind.** Audience is statisticians. Use the right words (`marginal`, `coarsen`, `FSA`, `haven_labelled`) without apology. But error messages should help, not scold — list the valid options, suggest a fix.
3. **A wink, not a routine.** The name is a pun. The `R` is magenta. The wordmark uses an italic serif. That's where the play ends — body copy is plain and useful.

### Voice patterns

| Pattern | Example |
| --- | --- |
| Second-person, direct | "Profile your data," "Pick a purpose." |
| Verbs first in CTAs | "Synthesise", "Compare", "Export bundle" |
| Lowercase API terms in `mono` | `ai_programming`, `coarsen_dates`, `rare_level_min_n` |
| Hedged claims around privacy | "intended to reduce direct disclosure risk, **not** to replace a formal privacy assessment" |
| Footnote-style asides | _"Relationship-aware synthesis is planned for a future release."_ |

### Casing

- **Sentence case** for headings, buttons, labels: _"Synthesis spec"_, not _"Synthesis Spec"_.
- **Code-style lowercase** for API values: `purpose = "ai_programming"`.
- The wordmark is the only place that uses irregular casing — **DataGangeR**, always with the capital `R`.

### "I" vs "you"

- **No "we" in product copy.** The product is a tool, not a personality.
- **"You" for the user.** "Your dataset", "you can share".
- **"DataGangeR" for the product** when attribution matters. _"DataGangeR will not tell you the output is safe for public release."_

### Emoji & ornament

- **No emoji** in product UI, docs, or marketing.
- Unicode dingbats (`→`, `·`, `—`) are fine and used as separators in CLI receipts and breadcrumbs.
- The closest thing to a mascot is the **double-R** glyph in the brand mark (see `assets/`).

### Examples (from the source)

- Hed: _"Synthetic Data Doubles for Safer Prototyping"_
- Subhed: _"Sharing the original data is not always possible. DataGangeR generates a synthetic doppelganger that preserves the structure, distributions, and relationships you need for development while reducing the need to expose original records."_
- Inline disclaimer: _"Synthetic data is intended to reduce direct disclosure risk, not to replace a formal privacy assessment."_
- Error: _"Purpose `internal_hifi` requires `acknowledge_risk = TRUE`. High-fidelity synthesis may preserve sensitive patterns. Set `acknowledge_risk = TRUE` to proceed."_

---

## VISUAL FOUNDATIONS

### The big idea — _doubles_

The whole identity riffs on the **doppelgänger**: every meaningful visual pair (column header / synthetic header, original distribution / synthetic distribution, profile chip / synth chip) is rendered as a **side-by-side pair** with one in **lichen green** (real / source) and one in **magenta** (synth / double). Even the wordmark embeds this idea: the `R` is the magenta double of the otherwise-ink lockup.

### Color

- **Paper base.** A warm off-white (`--paper-50: #FBFAF6`) — readable, journal-y, not the standard cold gray. The product handles serious data; the surface should feel like a notebook, not a SaaS dashboard.
- **Ink, not black.** `--ink-900: #11140F` — slightly green-tinted. Pairs cleanly with the paper.
- **Two roles, two colors.**
  - **Real / Source** = **lichen green** (`--real-500: #4F7D32`). Used for the original dataset everywhere it appears.
  - **Synth / Double** = **magenta** (`--synth-500: #D43A8A`). Used for the synthetic dataset, primary CTAs, focus rings, and the wordmark's `R`.
- **Risk = a separate burnt-orange.** Disclosure warnings live in `--risk-500: #C76B12` so they don't fight with the real/synth pair.
- **Status colors** (`info`, `success`, `danger`) exist but are used sparingly — most state changes are conveyed with the real/synth/risk palette.

### Type

- **Display + brand:** _Instrument Serif_ (italic for the gangster wink). Used for the wordmark, page hero, and big numbers.
- **UI:** _Inter_ — tight, neutral, tabular-figures-on. Body, labels, buttons, tables.
- **Data + code:** _JetBrains Mono_ — every variable name, every data value, every CLI receipt, every `purpose = "..."`.
- **Scale:** see `colors_and_type.css`. Anchored at 16px body, major-third up to 72px display.
- All three are loaded from Google Fonts (substitutes — see Caveats).

### Backgrounds

- **No photographic backgrounds.** The product is a data tool; imagery is a distraction.
- **No gradients on container surfaces.** Surfaces are flat paper.
- **One controlled gradient** is allowed on the primary CTA and the wordmark mark, as a thin top-highlight specular shine (see `--shine`). This is where the "shiny" in _Shiny app_ shows up visually.
- **Repeating motif:** a faint **scanline / tabular grid** texture (1px dots at 24px on `--paper-100`) used on hero sections to evoke a spreadsheet.

### Animation & motion

- **Calm and short.** 120–200ms for hovers, 240ms for panel transitions.
- **Easing:** `cubic-bezier(0.2, 0.8, 0.2, 1)` (entrance), `cubic-bezier(0.4, 0, 1, 1)` (exit).
- **No bounces, no springs, no shimmer loops.** This is a quiet UI.
- **The exception** is the wordmark's `R` on the marketing page — a one-shot 600ms glint that travels across the letterform on first paint, never repeats.

### Hover states

- **Buttons:** background darkens one step (`--synth-500 → --synth-700`); ink stays put.
- **Links & tertiary actions:** underline appears, color stays.
- **Cards:** shadow lifts from `--shadow-1` to `--shadow-2`, border tightens to `--border-strong`.
- **Rows in data tables:** background shifts to `--paper-100`; no border change.

### Press states

- **Buttons:** translate-Y(1px) and shadow drops to `--shadow-1`. Color does **not** shift further.
- **Tabs/segmented controls:** the active segment gets the inset `--shadow-inset` to read as pressed-in.

### Borders & dividers

- **Hairlines.** 1px solid `--border` (`#D7D0BB`). Dashed only for "drop a file here" upload zones.
- **Tabular rules** in data tables use `--paper-300` between rows, `--ink-900` for header underline.
- **Two-tone double rule** — a 2px stack of `--real-300` over `--synth-300` — is the package's signature divider. Used at the top of the export bundle and the comparison report.

### Shadow & elevation

- Three steps: `--shadow-1` (rest), `--shadow-2` (hover / popovers), `--shadow-3` (modals).
- **`--shine`** is the only "glossy" shadow and is reserved for: primary CTA, wordmark mark, the "Synthesise" action button in the Shiny app.
- **No inner shadows on inputs.** Inputs read as fields with a bottom rule, not as wells.

### Protection gradients vs capsules

- Tags and chips are **capsules** with a 1px border, not gradient backgrounds.
- The only protection treatment is on the brand mark when laid over imagery: a 50% white-paper plate beneath the wordmark with `backdrop-filter: blur(8px)`.

### Layout rules

- **Sidebar + main** for app screens. Sidebar is 280–320px, fixed, scrolls independently.
- **Max measure 72ch** for prose; data tables run full bleed within the main column.
- **The two-column compare layout** is the product's signature: identical-width columns titled "Original" (real) and "Synthetic" (synth) — and they are **always** in this left/right order.
- **8-column inner grid** at desktop, 4-column at tablet. Gutter `--space-6` (24px).

### Transparency & blur

- **Blur is rare.** Used only on the floating action bar at the bottom of the Shiny app (`backdrop-filter: blur(12px)` on `rgba(251,250,246,0.78)`).
- **Transparency in fills:** never below 40% on accents; you should always be able to tell what color something is.

### Imagery color vibe

- We don't ship photography.
- The one illustration in the brand kit is a **flat two-tone line drawing** of two overlapping silhouettes — _the double_ — in `--real-500` and `--synth-500`. See `assets/double-mark.svg`.

### Corner radii

- **2px** for inputs and chips (sharp; clerical).
- **4px** for buttons and small cards.
- **8px** for large cards and modals.
- **Pill** for tags only.

### Cards

A DataGangeR card is:

- `--paper-100` (or `--paper-50` if on a `--paper-100` surface) background
- 1px `--border` outline
- `--shadow-1` at rest, `--shadow-2` on hover
- `--radius-8` corner radius
- `--space-6` (24px) inner padding
- Header is a `.t-eyebrow` line (uppercase mono) above a `.t-h4` title

That's it — no left-border accent stripe, no colored backgrounds.

---

## ICONOGRAPHY

DataGangeR does **not** use a custom icon set. The package source contains no SVG icons; the Shiny app scaffold has no icon library either. To keep the UI honest and consistent we standardise on a single CDN library:

- **Library:** [**Lucide**](https://lucide.dev) (stroke-based, 1.5px, square caps). Loaded from CDN via the React build (`lucide-react`) or `https://unpkg.com/lucide-static`.
- **Why Lucide:** Stroke weight matches the paper-and-ink feel. Open-source, broadly available, ages well.
- **Stroke:** 1.5px at 20px size; 2px at 24px and above.
- **Color:** `currentColor` always. Default to `--ink-700`; `--synth-500` only on interactive primaries; `--real-500` for "source" affordances.
- **Sizing:** 16, 20, 24. Never under 16px.
- **No emoji.** No flag emoji, no smileys, no decorative unicode.
- **Unicode allowed:** `→` `·` `—` `·` `↳` for inline separators and "leads-to" relations in CLI receipts.

The brand mark itself ships in `assets/` as SVG (logomark, wordmark, double illustration).

---

## CAVEATS

- The `phase-5-shiny-brief-ming.md` brief was referenced but isn't on the public branch of `lennon-li/dataganger`. Visual direction is inferred from package source. **Please re-attach the brief and I'll align the spec to it.**
- The repo's `man/figures/logo.png` is referenced in the README but isn't in the importable tree. The logomark in `assets/` is an interpretation of the wordmark + "double R" concept. **If there's a canonical logo, drop it into `assets/` and I'll swap.**
- Web fonts are Google Fonts substitutes (Instrument Serif / Inter / JetBrains Mono). If the package has a brand font in mind, replace `fonts/` and update the `@import` line in `colors_and_type.css`.
- Icons standardise on Lucide. If you prefer Feather/Heroicons/Phosphor, the swap is mechanical.
