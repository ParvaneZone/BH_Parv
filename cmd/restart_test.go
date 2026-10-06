package cmd

import (
	"testing"
	"time"

	"github.com/ParvaneZone/BH_Parv/config"
)

func TestNextRestartDelay(t *testing.T) {
	now := time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)

	cases := []struct {
		name     string
		interval int
		at       []string
		want     time.Duration
		found    bool
	}{
		{"nothing configured", 0, nil, 0, false},
		{"interval only", 30, nil, 30 * time.Minute, true},
		{"daily time later today", 0, []string{"11:30"}, 90 * time.Minute, true},
		{"daily time already passed -> tomorrow", 0, []string{"09:00"}, 23 * time.Hour, true},
		{"interval wins when sooner", 30, []string{"11:30"}, 30 * time.Minute, true},
		{"daily wins when sooner", 600, []string{"10:15"}, 15 * time.Minute, true},
		{"invalid time ignored", 0, []string{"xx:yy"}, 0, false},
		{"exactly now rolls to tomorrow", 0, []string{"10:00"}, 24 * time.Hour, true},
	}
	for _, c := range cases {
		got, ok := nextRestartDelay(c.interval, c.at, now)
		if ok != c.found || (ok && got != c.want) {
			t.Errorf("%s: got (%v, %v), want (%v, %v)", c.name, got, ok, c.want, c.found)
		}
	}
}

func TestApplyDefaultsKCP(t *testing.T) {
	cfg := &config.Config{}
	applyDefaults(cfg)
	for _, s := range []struct {
		mode string
		mtu  int
		snd  int
		rcv  int
		d, p int
		buf  int
	}{
		{cfg.Server.KCPMode, cfg.Server.KCPMTU, cfg.Server.KCPSndWnd, cfg.Server.KCPRcvWnd, cfg.Server.KCPDataShard, cfg.Server.KCPParityShard, cfg.Server.KCPSockBuf},
		{cfg.Client.KCPMode, cfg.Client.KCPMTU, cfg.Client.KCPSndWnd, cfg.Client.KCPRcvWnd, cfg.Client.KCPDataShard, cfg.Client.KCPParityShard, cfg.Client.KCPSockBuf},
	} {
		if s.mode != "fast" || s.mtu != 1350 || s.snd != 1024 || s.rcv != 1024 || s.d != 0 || s.p != 0 || s.buf != 4194304 {
			t.Errorf("unexpected KCP defaults: %+v", s)
		}
	}

	// FEC needs both values > 0, otherwise it must be switched off.
	cfg = &config.Config{}
	cfg.Server.KCPDataShard = 3
	cfg.Server.KCPMode = "bogus"
	cfg.Server.KCPMTU = 100
	applyDefaults(cfg)
	if cfg.Server.KCPDataShard != 0 || cfg.Server.KCPParityShard != 0 {
		t.Errorf("half-configured FEC must be disabled, got %d/%d", cfg.Server.KCPDataShard, cfg.Server.KCPParityShard)
	}
	if cfg.Server.KCPMode != "fast" || cfg.Server.KCPMTU != 1350 {
		t.Errorf("invalid mode/mtu must fall back to defaults, got %q/%d", cfg.Server.KCPMode, cfg.Server.KCPMTU)
	}
}
