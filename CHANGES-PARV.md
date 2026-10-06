# BH_Parv changes (fork of Musixal/Backhaul; binary reports v0.7.4)

> These changes were written WITHOUT a Go toolchain available. Before use run:
> `go mod tidy && go vet ./... && go build ./...` and test on a staging pair of servers.
> The wire protocol is unchanged, so builds remain compatible with upstream Backhaul peers.

## Security
- No default token anymore (`musix` removed). Empty token => refuses to start; short tokens => warning.
- Token comparison is constant-time (all transports, server and client).
- The expected token is no longer printed into client logs on mismatch.
- wss/wssmux client: new options `tls_pin` (sha256 fingerprint of the server cert), `tls_verify`
  (full chain verification), `tls_sni` (custom SNI). TLS >= 1.2. Without pin/verify a warning is logged.
  Get the fingerprint: `openssl x509 -in server.crt -noout -fingerprint -sha256`

## Stability
- Reconnect sleeps use jitter (0.5x-1.5x of `retry_interval`) instead of a fixed interval.
- Copy buffers pooled (`sync.Pool`, 32 KB) instead of allocated per connection direction.

## Scheduled restart
- Config (`[server]` or `[client]`): `restart_interval = 360` (minutes) and/or `restart_at = ["04:30"]`
  (daily, local time). A random 0-30 s jitter is added. The process exits cleanly and relies on systemd
  `Restart=always` (already set by the installer scripts) to come back fresh.
- `backhaul-manager.sh` > Manage tunnels > option 12: set interval / daily time, or install a system cron
  entry in `/etc/cron.d/backhaul-restart-<name>` (removed automatically when the tunnel is deleted).

## KCP transport (`kcpmux`) - NEW, untested
- `transport = "kcpmux"` on both sides: smux multiplexing over KCP (UDP, pure Go, `xtaci/kcp-go`). The
  tunnel port is **UDP**. All KCP traffic is AES-256 encrypted with a key derived (PBKDF2) from `token`.
- NOT wire-compatible with upstream Backhaul (upstream has no kcpmux); both peers must run this fork.
- Options (`[server]`/`[client]`): `kcp_mode` = normal|fast|fast2|fast3 (default fast), `kcp_mtu` (1350),
  `kcp_sndwnd`/`kcp_rcvwnd` (1024), `kcp_datashard`+`kcp_parityshard` (FEC, default off, must match on both sides),
  `kcp_sockbuf` (4 MB; the kernel clamps it to `net.core.rmem_max`).
- Every pool session sends a token hello first (KCP sessions are invisible to the server until data arrives).
- `ParvBH` menu: kcpmux is a transport choice; option 8 = UDP connectivity test (receiver/sender, python3 needed).
- Before building: `go get github.com/xtaci/kcp-go/v5@latest && go mod tidy && gofmt -w . && go vet ./...`,
  then commit `go.mod` and `go.sum` (the release workflow needs them).

## Project
- Go module path is now `github.com/ParvaneZone/BH_Parv`.

## NOT included (honest list)
- No new transports (KCP/QUIC/DNS) and no DPI padding/uTLS: those need new dependencies and wire-protocol
  changes that cannot be verified without compiling and testing on real networks.

## Fixes round 2 (also untested without Go; run `go vet ./...` first)
- `backhaul.sh` no longer installs the upstream Musixal binary; it is now a thin wrapper that opens ParvBH.
- Manager: prerequisites (curl tar openssl python3 ss ip sha256sum, ca-certificates) are installed automatically at
  startup and before binary install; menu 9 = check/fix report; menu 8 = UDP test (installs python3 if missing).
- Manager: release binary is verified against `checksums.txt` (SHA-256); downloads are HTTPS/TLS1.2-only.
- wss/wssmux: server certificate fingerprint is embedded in the `BH1:` client string and written as `tls_pin`
  automatically (old 5-field strings still work, with a warning).
- Server no longer logs the token received from a failed handshake.
- pprof (6060/6061) and the web panel bind to 127.0.0.1 only (use `ssh -L` for remote access).
- systemd unit: NoNewPrivileges, PrivateTmp, ProtectHome.
- goreleaser: v2 `formats`, `ldflags`; linux amd64/arm64 only (matches the manager). Removed dead `httpserver.go`.

## Round 3 - review fixes (STILL not compiled or run by the author of this round: no Go toolchain, no network)
Run `go mod tidy && go vet ./... && go build ./... && go test -race ./...` before using anything. The new
`.github/workflows/ci.yml` does exactly that on every push.

### kcpmux
- Client: control channel now has a 120 s read deadline. UDP has no RST/keepalive, so a restarted/dead server
  used to leave the client blocked forever. Server heartbeat is clamped to <= 40 s for kcpmux (manager caps it too).
- Server: an authenticated peer (same IP + valid token) that opens a NEW control channel (e.g. client restarted)
  now makes the server tear down the dead one and re-handshake, instead of silently discarding it.
- `proxy_protocol = true` no longer breaks every connection on kcpmux: the PROXY v2 destination is taken from
  the incoming connection's local address instead of the tunnel peer's (UDP) address.
- Token shorter than 12 chars is now a hard error for kcpmux (the token is the only source of the AES key).
- KNOWN LIMITS (not fixed, needs a protocol change): kcp-go encryption has no real MAC (CRC32 only); the session
  filter is by source IP only; KCP traffic is random-looking UDP with no protocol mimicry.

### Robustness
- A forwarded port that cannot be bound (in use, bad range member) is logged and skipped; it no longer kills the
  whole tunnel (`Fatalf` -> `Errorf` in all `localListener`s).

### Manager / installer
- `valid_spec` now accepts exactly what the binary parses (PORT, A-B, LOCAL=PORT, LOCAL=HOST:PORT, IPv4:PORT=...)
  and range-checks ports. `4000:5000`, `1.2.3.4:443`, `99999`, `600-443` are rejected (they used to crash-loop the service).
- Ports are de-duplicated; `parse_conn_string` validates host, port, token, mux version.
- Default transport is now `wssmux` (pinned TLS). Plaintext transports (tcp, tcpmux, udp, ws, wsmux) are labelled
  and trigger a warning: the token and traffic are visible on the wire. A wss client without `tls_pin` now needs explicit confirmation.
- TLS certificate CN is random instead of the fixed `backhaul-<name>`.
- Binary install: `BH_VERSION=vX.Y.Z` pins a release; optional independent SHA-256 (`BH_SHA256` or prompt) for
  every source; custom URL must be https; archives with absolute/`..` paths are refused.
  NOTE: `checksums.txt` comes from the same release as the binary, so it only detects corruption, not a tampered release.
- `install.sh` / `ParvBH` update: `BH_REF=<tag-or-commit>` pins the script, syntax check, prints SHA-256, update asks for confirmation.
- Config files are created under `umask 077`; uninstall also removes the cron.d restart files.
- Messages fixed: Go >= 1.24 (matches go.mod); config edits are hot-reloaded within seconds (not "on next restart").

### Tests / CI
- Added unit tests (restart schedule, KCP defaults, token/jitter/fingerprint helpers, PROXY v2 header, KCP key derivation).
- Added CI (tidy check, vet, build, race tests, bash -n, shellcheck).
