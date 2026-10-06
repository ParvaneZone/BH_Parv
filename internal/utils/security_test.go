package utils

import (
	"testing"
	"time"
)

func TestTokenEqual(t *testing.T) {
	if !TokenEqual("secret-token-123", "secret-token-123") {
		t.Error("equal tokens must match")
	}
	if TokenEqual("secret-token-123", "secret-token-124") {
		t.Error("different tokens must not match")
	}
	if TokenEqual("", "x") || !TokenEqual("", "") {
		t.Error("empty-string handling is wrong")
	}
}

func TestNormalizeFingerprint(t *testing.T) {
	got := NormalizeFingerprint("  AA:bb:CC dd ")
	if got != "aabbccdd" {
		t.Errorf("got %q", got)
	}
}

func TestCertFingerprint(t *testing.T) {
	// SHA-256 of the empty input.
	const want = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	if got := CertFingerprint(nil); got != want {
		t.Errorf("got %s", got)
	}
}

func TestJitterRange(t *testing.T) {
	d := 10 * time.Second
	for i := 0; i < 2000; i++ {
		j := Jitter(d)
		if j < d/2 || j >= d+d/2 {
			t.Fatalf("jitter %v outside [%v, %v)", j, d/2, d+d/2)
		}
	}
	if Jitter(0) != 0 {
		t.Error("Jitter(0) must stay 0")
	}
}
