# Frozen generators: freeze once, generate many

Most of DataGangeR is a one-shot pipeline: read real data, review roles,
synthesize, compare, export. That is the right shape when you need one
bundle. It is the wrong shape when a team needs a fresh synthetic
dataset every week, or when a coding agent needs a new variation and the
person who owns the real data is not available to run synthesis again.

The frozen generator API is for that second case. A human opens the real
data **once**, reviews the policy, fits it, and signs off. After that,
generation is a bounded request against stored fitted state. The source
data is never reopened.

This is not the export bundle. The `recipe.yaml` in an export bundle
records the synthesis configuration; it is not a fitted generator and
cannot regenerate data by itself. Reruns from a recipe still require the
original data and a trusted human operator. A frozen generator is the
opposite trade: the fitted state is retained deliberately, in a private
store, under an explicit approval.

## Four words that are easy to conflate

The API has four distinct objects. Getting them straight makes
everything else follow.

### contract

The **contract** is the policy: what is allowed, independent of any
output.
[`generator_contract()`](https://dataganger.biostats.ai/reference/generator_contract.md)
builds one from three parts – the derived `policy` (output schema,
roles, and synthesis settings), the `allowed` request limits (permitted
seed, row-count, and dataset-count ranges), and a `compatibility` block
describing the runtime that produced it. The contract is immutable and
identified by `contract_id`, a hash of exactly those contents. Change
any of them and you have a different contract, with a different ID.

A contract carries no fitted state and no data. It is safe to show a
reviewer.

### generator

The **generator** is the fitted state produced by freezing a contract
against real data.
[`freeze_synthesis()`](https://dataganger.biostats.ai/reference/freeze_synthesis.md)
fits it, writes it to the private store, and returns a
`dataganger_frozen_generator` handle. The handle contains the public
contract and opaque references (`generator_id`, `generator_revision`,
`generator_fingerprint`, and the store location); it does **not**
contain the fitted state, so the handle itself is not the secret.

One contract can hold more than one fitted generator. Because the
contract is keyed by its policy rather than by the source data, freezing
two different datasets under the same spec, roles, and limits yields the
same `contract_id` but different `generator_id`s. That is deliberate,
not a defect: the contract describes what was permitted, the generator
describes what was fitted.
[`destroy_generator()`](https://dataganger.biostats.ai/reference/destroy_generator.md)
documents and relies on this – it destroys every fitted generator held
under the contract it is given.

### approval

The **approval** is the human sign-off, and it is a separate object from
both of the above.
[`approve_generator()`](https://dataganger.biostats.ai/reference/approve_generator.md)
records in the private store a binding between the public contract, one
specific fitted generator revision, the request limits, the compiler
version, the risk report, and a named `approver`. Generation is
unavailable until that record exists.

[`revoke_generator()`](https://dataganger.biostats.ai/reference/revoke_generator.md)
ends an approval; revocation is terminal for that contract ID and a
later approval must use a newly reviewed contract. Revocation is not
deletion – the fitted state and the exact-row material stay in the
store.

### request

The **request** is one bounded ask for a generation batch against an
approved generator.
[`generation_limits()`](https://dataganger.biostats.ai/reference/generation_limits.md)
defines the envelope the approver signed off on:

``` r

allowed <- generation_limits(
  n        = c(50L, 5000L),   # permitted output row counts
  datasets = c(1L, 5L),       # permitted variations per request
  seed     = c(0L, 1000L)     # permitted base seeds
)
```

Each call to
[`generate_synthetic()`](https://dataganger.biostats.ai/reference/generate_synthetic.md)
supplies a `seed`, `n`, and `datasets` overlay that must fall inside
that envelope. The request is hashed into a `request_id` and recorded in
a durable receipt. A request outside the approved range is refused; it
does not silently clamp.

So, in one line: a **contract** says what is permitted, a **generator**
is what was fitted, an **approval** binds one generator under one
contract for use, and a **request** is one bounded draw against that
approval.

## The walkthrough

### 1. Freeze

Freezing is the only step that touches the real data. It needs a `spec`
using the internal engine – V1 fitted generators require
`engine = "internal"`, and freezing a spec that resolves to anything
else fails with an `engine_ineligible` blocker – and an explicit,
persistent `store` path, so the handle can be reopened in a later R
session.

``` r

library(dataganger)

dat   <- read_input("my-data.csv")
roles <- detect_roles(dat)
spec  <- synth_spec(purpose = "development", roles = roles,
                    seed = 42, engine = "internal")

frozen <- freeze_synthesis(
  data    = dat,
  spec    = spec,
  roles   = roles,
  allowed = allowed,
  store   = "~/.dataganger-store"
)

frozen
#> DataGangeR frozen generator
#>   contract ID: 9f2c...
#>   generator ID: 41ab...
#>   eligible: TRUE
#>   store available: TRUE
#>   approved: FALSE
```

If the policy is not eligible for freezing,
[`freeze_synthesis()`](https://dataganger.biostats.ai/reference/freeze_synthesis.md)
errors and names the blockers. `generator_risk_report(frozen)` returns
the full fitting risk report for review.

Save the handle if you want it back later:

``` r

saveRDS(frozen, "frozen-handle.rds")
```

### 2. Approve

Review the risk report, then sign off. Nothing generates before this
succeeds.

``` r

approve_generator(frozen, approver = "a.reviewer")
```

`approver` must be one non-empty identity, and it is retained in the
store – including after destruction – so it stays clear who approved
what.

### 3. Generate

``` r

syn <- generate_synthetic(frozen, seed = 7, n = 500)

batch <- generate_synthetic(frozen, seed = 7, n = 500, datasets = 3)
summary(batch)
```

One dataset comes back as a `dataganger_synthetic` data frame; several
come back as a `dataganger_batch` with deterministic per-dataset seeds
and provenance. Every output carries a sanitized receipt:

``` r

generation_receipt(syn)
```

Generation runs a privacy check that fails closed. If the output cannot
be cleared – an exact source row reproduced, an infeasible k-anonymity
target, or an exact-row check that could not be performed at all – no
usable data is returned, and the error names the durable receipt ID so
the refusal itself is auditable.

### 4. Destroy, when it is done

``` r

destroy_generator(
  store       = "~/.dataganger-store",
  contract_id = frozen$contract_id,
  reason      = "project closed"
)
```

Destruction removes every fitted generator held under that contract,
including its exact-row index. It keeps the contract as a tombstone,
keeps the approval record marked `destroyed` with the original approver,
and keeps the generation receipts as an audit trail. It is idempotent
and irreversible.

One honest limit: destruction unlinks fitted state from the store. It is
not a secure wipe. On a journalling filesystem, an SSD with wear
levelling, a snapshotted volume, or any backup of the store, residual
copies may survive outside this package’s control. Read it as “removed
from the store and permanently unusable”, not as forensic erasure.

## The same lifecycle from the command line

``` sh
dataganger generator freeze my-data.csv --spec spec.yaml --store ~/store \
  --max-n 5000 --max-datasets 5
dataganger generator inspect  --store ~/store --contract-id <id>
dataganger generator status   --store ~/store
dataganger generator generate --store ~/store --contract-id <id> --out bundle.zip \
  --n 500 --datasets 3 --seed 7
dataganger generator revoke   --store ~/store --contract-id <id> --reason "..."
dataganger generator destroy  --store ~/store --contract-id <id> --reason "..."
```

Approval is deliberately not a CLI subcommand: it is a human review
action taken in R or in the app.

## Reproducibility: what is actually guaranteed

Two calls with the same approved contract and the same request produce
the same bytes – but only inside a recorded compatibility envelope. The
envelope is real and machine-checked, and it is narrower than “this
always reproduces”.

What the fitted state records as its compatibility block is:

- the engine (`internal`),
- the package name and the **DataGangeR package version**,
- the generator schema version,
- the seed algorithm identifier (`dataganger-seed-v1`),
- the canonical data-hash algorithm identifier.

What is checked: every time a frozen handle is validated – which
includes every
[`generate_synthetic()`](https://dataganger.biostats.ai/reference/generate_synthetic.md)
call – the stored contract’s compatibility block is compared against the
compatibility derived from the *running* DataGangeR runtime. A mismatch
fails closed with “Contract compatibility is not derived from this
DataGangeR runtime.” In practice this means **upgrading or downgrading
DataGangeR invalidates an existing frozen generator**: it does not
quietly generate slightly different data, it refuses.

The runtime also pins the RNG kinds it draws under (Mersenne-Twister /
Inversion / Rejection) rather than inheriting the caller’s ambient
[`RNGkind()`](https://rdrr.io/r/base/Random.html), and derives each
effective seed from the approved contract ID, so an identical approved
request is not perturbed by session state.

What is **not** recorded, and therefore not promised:

- The **R version** is not part of the stored compatibility block. If a
  future R release changes the behaviour of the pinned RNG or of any
  numeric formatting the generator depends on, byte-identical
  reproduction across that change is not guaranteed and is not claimed
  here.
- Nothing outside the recorded fields is covered. Byte-for-byte
  reproduction is guaranteed only under the recorded envelope. It is not
  a general promise across arbitrary version changes, and it should not
  be relied on as one.

If byte-identical regeneration matters to you, pin the DataGangeR
version and the R version alongside the store, and treat the receipt
hashes as the evidence of what was actually produced.

## Migration: generators frozen before the exact-row portability fix

The exact-row privacy check hashes each source row into a keyed
fingerprint index so generated output can be checked for verbatim source
rows. That fingerprint algorithm was changed to a portable, canonical
form (`HMAC-SHA256-canonical-v1`); the earlier form is recorded as
`HMAC-SHA256`.

**A generator frozen before that fix cannot be checked by the current
runtime.** Rather than pass output that was never actually screened, the
check fails closed. You will see a blocker with code
`exact_row_check_unavailable` and a message along these lines:

> The exact-row privacy check could not be performed and the output is
> therefore not cleared. The stored index uses the legacy exact-row
> algorithm; the generator must be re-frozen and re-approved because the
> exact-row algorithm changed.

What it means: the stored index is in the old format, so the runtime
cannot tell whether the generated rows reproduce real ones. No data is
returned.

What to do: re-freeze and re-approve.

1.  Re-run
    [`freeze_synthesis()`](https://dataganger.biostats.ai/reference/freeze_synthesis.md)
    on the source data with the same spec, roles, and limits. This fits
    a new generator with a current-format exact-row index.
2.  Review the new risk report.
3.  Call
    [`approve_generator()`](https://dataganger.biostats.ai/reference/approve_generator.md)
    on the new handle.
4.  Once you are satisfied the replacement works,
    [`destroy_generator()`](https://dataganger.biostats.ai/reference/destroy_generator.md)
    the old contract.

There is no in-place upgrade path, and that is on purpose: the index is
derived from the real data, so it cannot be rebuilt without the real
data. Anyone holding only the old store cannot silently fix it – they
have to go back to a person who has the source.

The same fail-closed behaviour applies whenever the exact-row index is
missing or malformed, with the shorter message “The generator must be
re-frozen.”

## The Agent generate-only route

A frozen generator makes it possible for a coding agent to obtain a
fresh synthetic bundle without any access to the real data, using a
two-process route:

``` sh
dataganger agent status   --contract-id <id>
dataganger agent generate --contract-id <id> --out bundle.zip --n 500
```

The agent client accepts a contract ID and bounded request fields only –
no store path, no data path, no privacy acknowledgement or opt-out.
Freezing, approval, revocation, inspection, and migration are not
reachable from it; they remain human operator actions. The client never
opens the private store. It reaches a **broker** process
(`dataganger generator-broker --store <dir>`), which runs as the
store-owning account and is the only code on this route that opens the
store, through exactly one host-whitelisted invocation named by the
`DATAGANGER_AGENT_BROKER` environment variable.

### Where the isolation actually comes from

State this precisely, because it is easy to overclaim:

**DataGangeR does not create the Agent-mode isolation boundary. The host
does.** In-process package code cannot create a boundary against a
caller running as the same OS user, so any such claim would be false.
What the package ships is both halves of the route and the handshake
that *verifies* isolation the host has already established. Agent mode
becomes available only when the running process proves at runtime that
it **cannot** read the private store as the current user; a successful
read means no boundary exists, in which case Agent mode reports itself
unavailable and states why, and no generation occurs.

That is deliberately an observable negative – “I just tried to read the
private state and was refused” – rather than an unprovable positive
assertion. It is the only isolation claim package code can honestly
make, and it cannot be satisfied by documentation alone.

`dataganger agent status` reports `available` only when all of the
following hold, each failing closed: a broker invocation is configured;
the broker answers the capabilities probe with its own principal, store
root, and the contract’s public limits; the broker’s principal differs
from the client’s (equal means same-user, which is policy, not a
boundary); the client is not a superuser, since root defeats permission
bits and its read refusal would prove nothing; and the client’s real
attempted read of the store marker and real listing of `generators/`
both fail. Anything unexpected reports `unavailable`, never `available`.

A same-user wrapper that merely refuses privileged subcommands is policy
only. It does not satisfy the structural claim and must not be presented
as isolation.

For the reference host configuration – the service account, the `0700`
store, the single whitelisted `sudoers` or Windows ACL invocation, and
how to verify it – see `HOST-SETUP.md` in the packaged agent skill
(`system.file("agent-skill", "HOST-SETUP.md", package = "dataganger")`).
That setup is documented but not implemented by the package, and it is
deliberately not duplicated here.

## What this does not change

A frozen generator changes who can press the button and how often. It
does not change what the output is. Generated data is still synthetic
data: it carries the same fidelity limits, the same disclosure warnings,
and the same blockers as any other DataGangeR output, and the bundle’s
`manifest.json` should still be read before the data is used. Synthetic
output can reduce direct disclosure risk; it does not guarantee
anonymity, regulatory compliance, or safe public release.

See the [privacy gating and Agent workflows
vignette](https://dataganger.biostats.ai/articles/privacy-and-ai-workflow.html)
for the wider privacy model.
