package utils

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"math/rand"
	"strings"
	"time"
)

// TokenEqual compares two tokens in constant time to avoid timing side channels.
func TokenEqual(a, b string) bool {
	ha := sha256.Sum256([]byte(a))
	hb := sha256.Sum256([]byte(b))
	return subtle.ConstantTimeCompare(ha[:], hb[:]) == 1
}

// NormalizeFingerprint lowercases a hex SHA-256 fingerprint and strips ':' and spaces.
func NormalizeFingerprint(fp string) string {
	fp = strings.ToLower(strings.TrimSpace(fp))
	fp = strings.ReplaceAll(fp, ":", "")
	fp = strings.ReplaceAll(fp, " ", "")
	return fp
}

// CertFingerprint returns the hex SHA-256 fingerprint of a DER certificate.
func CertFingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	return hex.EncodeToString(sum[:])
}

// Jitter returns d randomized in the range [0.5d, 1.5d) so that many clients
// do not reconnect in lockstep (and so retry timing is not a fixed pattern).
func Jitter(d time.Duration) time.Duration {
	if d <= 0 {
		return d
	}
	half := int64(d) / 2
	return time.Duration(half + rand.Int63n(int64(d)))
}
