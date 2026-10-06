package handlers

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"testing"
)

func TestBuildProxyProtocolV2HeaderIPv4(t *testing.T) {
	h, err := buildProxyProtocolV2Header("1.2.3.4", "5.6.7.8", 1111, 2222)
	if err != nil {
		t.Fatal(err)
	}
	if len(h) != 28 {
		t.Fatalf("len = %d, want 28", len(h))
	}
	if !bytes.Equal(h[:12], []byte{0x0d, 0x0a, 0x0d, 0x0a, 0x00, 0x0d, 0x0a, 0x51, 0x55, 0x49, 0x54, 0x0a}) {
		t.Error("bad signature")
	}
	if h[12] != 0x21 || h[13] != 0x11 || binary.BigEndian.Uint16(h[14:16]) != 12 {
		t.Errorf("bad version/family/length: %x %x %d", h[12], h[13], binary.BigEndian.Uint16(h[14:16]))
	}
	if binary.BigEndian.Uint16(h[24:26]) != 1111 || binary.BigEndian.Uint16(h[26:28]) != 2222 {
		t.Error("bad ports")
	}
}

func TestBuildProxyProtocolV2HeaderIPv6(t *testing.T) {
	h, err := buildProxyProtocolV2Header("2001:db8::1", "2001:db8::2", 1, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(h) != 52 || h[13] != 0x21 || binary.BigEndian.Uint16(h[14:16]) != 36 {
		t.Errorf("unexpected IPv6 header: len=%d family=%x", len(h), h[13])
	}
}

func TestBuildProxyProtocolV2HeaderInvalidIP(t *testing.T) {
	if _, err := buildProxyProtocolV2Header("nope", "5.6.7.8", 1, 2); err == nil {
		t.Error("expected an error for an invalid IP")
	}
}

// Regression: the destination must come from the incoming connection's local
// address, so it also works when the "to" side is not a TCP connection (kcpmux).
func TestWriteProxyProtocolDoesNotNeedTCPPeer(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Skip("cannot listen on loopback:", err)
	}
	defer ln.Close()

	done := make(chan net.Conn, 1)
	go func() {
		c, _ := ln.Accept()
		done <- c
	}()
	client, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	incoming := <-done
	defer incoming.Close()

	a, b := net.Pipe() // not a TCP connection, like an smux stream over KCP
	defer a.Close()
	defer b.Close()

	got := make(chan []byte, 1)
	go func() {
		buf := make([]byte, 28)
		_, _ = io.ReadFull(b, buf)
		got <- buf
	}()

	if err := WriteProxyProtocol(incoming, a); err != nil {
		t.Fatalf("WriteProxyProtocol: %v", err)
	}
	h := <-got
	if h[12] != 0x21 || h[13] != 0x11 {
		t.Errorf("unexpected header %x", h[:16])
	}
}
