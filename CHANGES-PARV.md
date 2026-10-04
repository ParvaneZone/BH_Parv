# BH_Parv changes (on top of Backhaul v0.7.2)

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
