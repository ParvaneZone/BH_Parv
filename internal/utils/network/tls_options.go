package network

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
	"net"
	"sync"

	"github.com/ParvaneZone/BH_Parv/internal/utils"
)

// TLSOptions controls how the wss / wssmux client validates the server.
type TLSOptions struct {
	Verify bool   // full chain + hostname verification
	Pin    string // hex sha256 fingerprint of the server leaf certificate
	SNI    string // custom server name sent in the TLS ClientHello
}

var (
	tlsOptsMu sync.RWMutex
	tlsOpts   TLSOptions
)

// SetTLSOptions must be called before the client starts dialing.
func SetTLSOptions(o TLSOptions) {
	o.Pin = utils.NormalizeFingerprint(o.Pin)
	tlsOptsMu.Lock()
	tlsOpts = o
	tlsOptsMu.Unlock()
}

// BuildClientTLSConfig builds the tls.Config used by the websocket dialer.
// Default (no options) keeps the previous behaviour (no verification) so
// existing self-signed setups keep working; pin or verify make it strict.
func BuildClientTLSConfig(addr string) *tls.Config {
	tlsOptsMu.RLock()
	o := tlsOpts
	tlsOptsMu.RUnlock()

	cfg := &tls.Config{MinVersion: tls.VersionTLS12}

	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
	}
	if o.SNI != "" {
		cfg.ServerName = o.SNI
	} else {
		cfg.ServerName = host
	}

	switch {
	case o.Pin != "":
		pin := o.Pin
		cfg.InsecureSkipVerify = true // chain check replaced by the pin check below
		cfg.VerifyPeerCertificate = func(raw [][]byte, _ [][]*x509.Certificate) error {
			if len(raw) == 0 {
				return errors.New("tls: server sent no certificate")
			}
			if utils.CertFingerprint(raw[0]) != pin {
				return errors.New("tls: server certificate fingerprint does not match tls_pin")
			}
			return nil
		}
	case o.Verify:
		cfg.InsecureSkipVerify = false
	default:
		cfg.InsecureSkipVerify = true
	}
	return cfg
}
