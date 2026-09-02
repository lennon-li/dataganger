# Reference host configuration for the generate-only agent route

The DataGangeR package ships both halves of the agent route and the handshake
that verifies isolation. It does not create the isolation. The host does.

A single process cannot both prove it cannot read the private store and then
generate from that store, because generation requires reading fitted state. The
route therefore separates the principals into two processes:

- **Broker** -- `dataganger generator-broker --store <dir>` -- runs as the
  store-owning account. It is the only code on this route that opens the
  private store. It reads one JSON request on stdin and writes one JSON
  response on stdout.
- **Agent client** -- `dataganger agent generate ...` -- runs as a different
  account with no read access to the store, and never opens the store. It
  invokes the broker through one host-whitelisted command named by the
  `DATAGANGER_AGENT_BROKER` environment variable.

## What the host must supply

1. A separate account that owns the private store.
2. Store ownership at mode `0700`, so the agent account is genuinely refused.
3. Exactly one whitelisted invocation from the agent account to the broker.

Container or namespace isolation satisfies the same handshake with no extra
package configuration.

## Linux and macOS

Create the store-owning account and lock the store:

```sh
sudo useradd --system --home /srv/dataganger dgstore
sudo install -d -o dgstore -g dgstore -m 0700 /srv/dataganger/store
```

Whitelist exactly one command in `sudoers` (via `visudo`):

```
dgagent ALL=(dgstore) NOPASSWD: /usr/local/bin/dataganger generator-broker --store /srv/dataganger/store
```

Then, in the agent account's environment:

```sh
export DATAGANGER_AGENT_BROKER="sudo -n -u dgstore /usr/local/bin/dataganger generator-broker --store /srv/dataganger/store"
```

The invocation is split on whitespace and executed directly, without a shell,
so it must not rely on quoting, globbing, or shell expansion -- and no path in
it may contain spaces.

## Windows

Run the broker under a dedicated service account that owns the store, and set a
DACL that denies the agent account read access to the store directory. Point
`DATAGANGER_AGENT_BROKER` at the whitelisted invocation for that service
account. The handshake compares SIDs rather than uids on Windows. Verify this
configuration manually: `file.access()` does not reflect ACL denials reliably
on Windows, so an unreliable result is treated as "readable" and the route
reports itself unavailable rather than risk a false boundary.

## Verifying the configuration

From the agent account:

```sh
dataganger agent status --contract-id <id>
```

`available` requires all of the following, each failing closed:

1. A broker invocation is configured.
2. The broker answers the capabilities probe with its own principal, its store
   root, and the contract's public limits.
3. The broker's principal differs from the client's. Equal means same-user,
   which is policy, not a boundary.
4. The client is not a superuser, since root defeats permission bits and its
   read refusal would prove nothing.
5. The client's real attempted read of the store marker and real listing of
   `generators/` both fail.

Anything unexpected reports `unavailable`, never `available`.

The package's own test suite exercises every refusal path, but it cannot create
a second account, so the end-to-end success path is gated. To run it against a
configured host:

```sh
export DATAGANGER_AGENT_E2E=true
export DATAGANGER_AGENT_E2E_CONTRACT=<approved contract id>
export DATAGANGER_AGENT_BROKER="..."
R -e 'testthat::test_local(filter = "agent-boundary")'
```
