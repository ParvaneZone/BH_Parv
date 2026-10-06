package network

import "testing"

func TestKCPBlockDeterministic(t *testing.T) {
	b1, err := KCPBlock("0123456789abcdef")
	if err != nil {
		t.Fatal(err)
	}
	b2, _ := KCPBlock("0123456789abcdef")
	b3, _ := KCPBlock("0123456789abcdeg")

	src := make([]byte, 64)
	for i := range src {
		src[i] = byte(i)
	}
	e1 := make([]byte, 64)
	e2 := make([]byte, 64)
	e3 := make([]byte, 64)
	b1.Encrypt(e1, src)
	b2.Encrypt(e2, src)
	b3.Encrypt(e3, src)
	if string(e1) != string(e2) {
		t.Error("same token must derive the same key")
	}
	if string(e1) == string(e3) {
		t.Error("different tokens must derive different keys")
	}
}
