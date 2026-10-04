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

## Project
- Go module path is now `github.com/ParvaneZone/BH_Parv`.

## NOT included (honest list)
- No new transports (KCP/QUIC/DNS) and no DPI padding/uTLS: those need new dependencies and wire-protocol
  changes that cannot be verified without compiling and testing on real networks.
