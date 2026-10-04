package cmd

import (
	"context"
	"math/rand"
	"os"
	"strings"
	"time"
)

// nextRestartDelay returns how long to wait until the next scheduled restart.
// It considers both restart_interval (minutes) and restart_at (daily "HH:MM"
// local times) and picks whichever comes first.
func nextRestartDelay(intervalMin int, at []string, now time.Time) (time.Duration, bool) {
	var best time.Duration
	found := false
	consider := func(d time.Duration) {
		if d <= 0 {
			return
		}
		if !found || d < best {
			best, found = d, true
		}
	}

	if intervalMin > 0 {
		consider(time.Duration(intervalMin) * time.Minute)
	}
	for _, s := range at {
		t, err := time.Parse("15:04", strings.TrimSpace(s))
		if err != nil {
			logger.Warnf("ignoring invalid restart_at value %q (expected HH:MM)", s)
			continue
		}
		next := time.Date(now.Year(), now.Month(), now.Day(), t.Hour(), t.Minute(), 0, 0, now.Location())
		if !next.After(now) {
			next = next.AddDate(0, 0, 1)
		}
		consider(next.Sub(now))
	}
	return best, found
}

// scheduleRestart arms a one-shot timer. When it fires the tunnel is stopped
// cleanly and the process exits with code 0. A supervisor (systemd with
// Restart=always, which the installer scripts configure) then starts a fresh
// process, so every listener/port/goroutine starts from a clean state.
func scheduleRestart(ctx context.Context, intervalMin int, at []string, stop func()) {
	d, ok := nextRestartDelay(intervalMin, at, time.Now())
	if !ok {
		return
	}
	// up to 30s of jitter so a fleet of tunnels does not restart in lockstep
	d += time.Duration(rand.Int63n(int64(30 * time.Second)))

	logger.Infof("scheduled restart in %s (requires a supervisor such as systemd Restart=always)", d.Round(time.Second))

	go func() {
		timer := time.NewTimer(d)
		defer timer.Stop()
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			logger.Info("scheduled restart: stopping tunnel, the service manager will start it again")
			stop()
			time.Sleep(2 * time.Second)
			os.Exit(0)
		}
	}()
}

// validateToken refuses to run without a token and warns about weak ones.
func validateToken(role, token string) {
	if token == "" {
		logger.Fatalf("%s token is empty: set a strong 'token' in the config (there is no default token)", role)
	}
	if len(token) < 12 || token == "musix" {
		logger.Warnf("%s token is weak: use at least 12 random characters (e.g. `openssl rand -hex 16`)", role)
	}
}
