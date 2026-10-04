package network

import (
	"crypto/sha1"
	"fmt"

	"github.com/xtaci/kcp-go/v5"
	"golang.org/x/crypto/pbkdf2"
)

// KCPOptions holds the tunables of the kcpmux transport.
// FEC (DataShard/ParityShard) and the token must be identical on both sides.
type KCPOptions struct {
	Mode        string // normal | fast | fast2 | fast3
	MTU         int
	SndWnd      int
	RcvWnd      int
	DataShard   int // 0 = FEC disabled
	ParityShard int
	SockBuf     int // UDP socket buffer in bytes, 0 = OS default
}

// KCPBlock derives an AES-256 block cipher from the shared token, so all KCP
// traffic is encrypted and unauthenticated peers cannot talk to the listener.
func KCPBlock(token string) (kcp.BlockCrypt, error) {
	key := pbkdf2.Key([]byte(token), []byte("BH_Parv-kcpmux-v1"), 4096, 32, sha1.New)
	return kcp.NewAESBlockCrypt(key)
}

// KCPApplyTuning configures a session (client or accepted server side).
func KCPApplyTuning(s *kcp.UDPSession, o KCPOptions) {
	var nodelay, interval, resend, nc int
	switch o.Mode {
	case "normal":
		nodelay, interval, resend, nc = 0, 40, 2, 1
	case "fast2":
		nodelay, interval, resend, nc = 1, 20, 2, 1
	case "fast3":
		nodelay, interval, resend, nc = 1, 10, 2, 1
	default: // "fast"
		nodelay, interval, resend, nc = 0, 30, 2, 1
	}
	s.SetStreamMode(true)
	s.SetWriteDelay(false)
	s.SetNoDelay(nodelay, interval, resend, nc)
	s.SetWindowSize(o.SndWnd, o.RcvWnd)
	s.SetMtu(o.MTU)
	s.SetACKNoDelay(true)
	if o.SockBuf > 0 {
		_ = s.SetReadBuffer(o.SockBuf)
		_ = s.SetWriteBuffer(o.SockBuf)
	}
}

// KCPDial opens a KCP session to addr. Note: UDP has no handshake, so a nil
// error does NOT mean the server is reachable; the token exchange that follows
// is what proves it.
func KCPDial(addr, token string, o KCPOptions) (*kcp.UDPSession, error) {
	block, err := KCPBlock(token)
	if err != nil {
		return nil, fmt.Errorf("kcp crypt: %w", err)
	}
	s, err := kcp.DialWithOptions(addr, block, o.DataShard, o.ParityShard)
	if err != nil {
		return nil, err
	}
	KCPApplyTuning(s, o)
	return s, nil
}

// KCPListen starts a KCP listener on addr.
func KCPListen(addr, token string, o KCPOptions) (*kcp.Listener, error) {
	block, err := KCPBlock(token)
	if err != nil {
		return nil, fmt.Errorf("kcp crypt: %w", err)
	}
	l, err := kcp.ListenWithOptions(addr, block, o.DataShard, o.ParityShard)
	if err != nil {
		return nil, err
	}
	if o.SockBuf > 0 {
		_ = l.SetReadBuffer(o.SockBuf)
		_ = l.SetWriteBuffer(o.SockBuf)
	}
	return l, nil
}
