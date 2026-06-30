# DataGangeR — package spine & trust architecture

Canonical statement of what the package *is* and the guarantees it makes. Source of truth for
the user-facing manual/vignette (Phase 5). Last updated 2026-06-29.

Status markers: **[NOW]** = true in the current codebase; **[PLANNED]** = designed, tracked in
`dev/plans/2026-06-29-guardrail-comparison-agent-skill-implementation.md`, not yet implemented.

> Update 2026-06-29: Phases 1-4 + 6 are implemented on branch
> `feature/v0.5.0-guardrail-comparison-agent-skill` (pending merge to main / CRAN). Items below
> marked "[NOW, branch]" are live on that branch. Phase 5 (vignette) is the only remaining piece.

---

## 1. The spine (one promise)

**As a human, you decide the privacy rules once. Then you either hand the AI safe synthetic
data, or hand the AI the package plus your saved rules so it generates safe data itself — the
AI never touches the real data, and nothing ever leaves your machine.**

### Two usage paths
- **Path A — data hand-off:** human gates privacy in the UI -> generates a synthetic bundle ->
  gives the *bundle* to the AI. The AI gets safe data, nothing else.
- **Path B — delegated generation:** human gates privacy -> saves the config (`spec.yaml` +
  `roles.yaml` + seed) -> the AI runs the package/CLI with that config to generate synthetic
  data (and variations) itself, reproducing the human's exact decisions. The AI calls the
  package but is structurally barred from reading the real data. **[NOW]** parity (CLI
  `--roles`) + the agents-only `SKILL.md` ("You are not allowed to read the original data") ship
  this; the first agent step is to reproduce the UI's CSV byte-for-byte before doing anything.

### The privacy gating ladder (UI), mapped to the 3 disclosure-control categories
1. Entry gate — disclaimer + attest "no direct identifiers"; refuse -> shutdown. => **direct
   identifiers** **[PLANNED]**
2. Upload **[PLANNED order change: upload-first]**
3. Soft fail-safe (early) — scan; flag suspected direct identifiers -> drop / confirm / abort.
   => safety net for direct identifiers **[PLANNED]**
4. Objective preset **[NOW]**
5. Configure, two questions per column — Q1 "could this, combined with others, single out a
   person?" (none/combination) => **quasi-identifiers**; Q2 "is this sensitive?" => **sensitive
   attributes**. Hard gate until every column is answered. **[NOW]** (two-axis model + gate)
6. Synthesis enforcement — k-anonymity on quasi-identifiers, treatment of sensitive cols,
   drops. **[NOW]**
7. Compare + privacy report — fidelity + disclosure metrics. **[NOW]** (inference-aware stats
   shipped this cycle)
8. Export — synthetic bundle (Path A) and/or saved config (Path B). **[NOW]**

What the two questions reinforce: after attesting no direct identifiers, Q1 reinforces
*linkage* risk (combinations re-identify) and Q2 reinforces that *harm != identification*
(sensitivity is independent). The attestation handles the obvious category; the two questions
carry the two subtler ones, so the user does not falsely feel "done" after removing names.

---

## 2. What prevents internet usage (the no-network guarantee)

Goal: **the package never accesses the internet — whether the internet is on or off.** Turning
wi-fi off only proves offline operation; it does not disprove phoning-home when connected. The
real guarantee rests on two structural locks plus auditable proofs.

### Two structural locks
- **No network code (can't send).** The package's own code makes no outbound calls — no
  `url()`, `download.file()`, `socketConnection()`, `httr`/`curl`/`RCurl`, no sockets. **[NOW]**
  for the core data path (profile / detect_roles / synthesize_data / compare_synthetic /
  privacy_check / export_synthetic / CLI). The Shiny app serves only on localhost.
  - **[PLANNED] Phase 6 — remove the one exception for an absolute claim.** Today
    `report_issue()` (the "Report a problem" button) calls `utils::browseURL()` to open the
    user's browser at a prefilled GitHub issue (only version/OS metadata + the user's message;
    no dataset content; user-initiated). To make the no-network claim *unconditional* (Lennon,
    2026-06-29), `report_issue()` will **no longer auto-open the browser** — it will print/return
    the prefilled issue text + URL, and the UI button will show a **copyable modal**. The user
    copies it into their own browser. After this, the package contains **no** `browseURL` and the
    source-grep guard needs **no whitelist** — "zero network-related calls, no exceptions."
- **Nothing is persisted (nothing to send later).** Real data is read into memory only; the app
  writes nothing to disk except the synthetic bundle the user chooses to export. When the app
  closes, the in-memory data is gone — so "internet comes back on later" has nothing to send.
  **[NOW]**

Together these defeat the "internet returns -> it uploads" argument: there is no code to send,
and no retained data to be sent.

### The one current outbound request (being removed)
- The Shiny UI `@import`s web fonts from the Google Fonts CDN
  (`inst/app/www/colors_and_type.css`). This is a browser-side style request, not the R package
  sending data — but it is the only thing that reaches the network. **[PLANNED]** Phase 6
  self-hosts the fonts (`inst/app/www/fonts/`) and removes the CDN import, after which the app
  has **zero** external requests.

### Honest "we don't read" framing
The package *must* read the file into memory to detect identifiers — you cannot catch what you
do not scan. The truthful claim is therefore: **"we scan locally to find and drop direct
identifiers; we never upload; we never keep."** Not "we don't read direct identifiers" (false).

### Proofs (strongest first) — **[PLANNED]** Phase 6
1. **Runtime trap test.** Stub the base network primitives (`url`, `download.file`,
   `socketConnection`, + curl/httr) so any call errors, then run the full pipeline + app
   construction. Completion = zero network attempts. Internet-state-independent; also catches a
   dependency trying to phone home (they go through the same primitives). Runs in CI.
2. **Source-grep guard.** A test that fails the build if any network symbol appears in `R/`.
   Makes "no network code" an enforced, ongoing invariant.
3. **Open source / auditable.** It is on CRAN and on GitHub: don't trust — read the code and run
   the trap test yourself. (No closed binary can offer this.)
4. **Offline CI job.** `unshare -rn Rscript -e 'testthat::test_local(".")'` on a Linux runner —
   platform-independent proof the source opens no connections (covers Windows/macOS, same code).
5. **Live egress monitor with internet ON** (for users who will not disconnect): watch the R
   process — Windows Resource Monitor / Process Monitor / Wireshark; Linux `strace`/`ss` — and
   observe zero connections during a full run.

### Demonstrating it per OS (optional extra; guarantee is the same code everywhere)
- Any OS: disconnect wi-fi, run `dataganger::run_app()`, complete the workflow.
- Linux: `unshare -rn Rscript -e 'dataganger::run_app()'`.
- Windows: disable adapter / Airplane mode; or a Defender Firewall outbound-block rule on
  `Rscript.exe`/`R.exe`; or Windows Sandbox with `<Networking>Disable</Networking>`.
- macOS: turn off wi-fi, or a `pf` block rule.

---

## 2b. Supply-chain / anti-backdoor defenses (open-source risk)

Open source is also a *risk*: a malicious contributor (or compromised maintainer account, or a
poisoned dependency) could add silent data-stealing code after the project earns trust (cf.
xz-utils, event-stream). You cannot make this impossible, but you can make silent theft
**break an automated test anyone can run**. Key insight: **the no-network machinery (section 2)
IS the anti-backdoor defense** — exfiltration needs a channel, and every channel is watched.

- **Every exfiltration path is caught:** network code -> source-grep guard (build) + runtime
  trap (test); `system()`/shell-out to `curl` -> the **offline CI namespace** (`unshare -rn`)
  is *method-agnostic*: no network exists, so any attempt fails regardless of how it is written.
  A backdoor that phones home **breaks CI**. **[PLANNED]** Phase 6.
- **Hard to inject:** branch protection on `main` (no direct pushes; required review; signed
  commits), 2FA on GitHub + CRAN, protected maintainer email. **[PLANNED ops]**
- **Smaller surface:** minimal, pinned dependencies (attacks often arrive via a dependency
  update; the runtime trap catches a dependency phoning home too). **[ongoing]**
- **CRAN as a checkpoint:** users install reviewed, checked CRAN releases (tagged, checksummed),
  not arbitrary GitHub commits. **[NOW]** (CRAN submission in progress)
- **Point-of-use verification (strongest):** because the package is open source *and ships the
  no-network self-test*, a user/IT can run the trap test against the exact installed version and
  confirm it makes zero network calls — no need to trust the maintainer or supply chain. A
  closed binary cannot offer this. **[PLANNED]** Phase 6 (ship the test).
- **Honest limit:** a sophisticated backdoor in a transitive dependency, crafted to evade these
  specific checks, could in theory slip through — no project is immune. But the layered posture
  above means data theft cannot be *silent*: it must break a test someone can run.

## 3. Summary table

| Property | Mechanism | Status |
|---|---|---|
| Human sets rules once | entry gate + two-axis Configure | [NOW] (gate [PLANNED]) |
| AI never reads real data | Path B: `--roles` parity + agent SKILL.md | [NOW] |
| AI gets only safe data | Path A: synthetic bundle export | [NOW] |
| No network code | no network primitives in source | [NOW] core; guard [NOW, branch] |
| No browser-launch either | report_issue prints/copies, no browseURL | [NOW, branch] |
| Nothing persisted | in-memory only; export is opt-in | [NOW] |
| No external requests at all | self-host fonts (remove CDN) | [NOW, branch] |
| Provable no-internet | runtime trap test + source guard + offline CI | [NOW, branch] |
