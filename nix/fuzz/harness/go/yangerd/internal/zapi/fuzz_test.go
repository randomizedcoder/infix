// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package zapi

import (
	"bytes"
	"testing"
)

// FuzzDecodeHeader and FuzzReadMessage: what zebra sends yangerd over ZAPI.
func FuzzDecodeHeader(f *testing.F) {
	f.Add(EncodeHello())
	f.Add(EncodeRouterIDAdd(2))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = DecodeHeader(data)
	})
}

func FuzzReadMessage(f *testing.F) {
	f.Add(EncodeHello())
	f.Add(append(EncodeRouterIDAdd(2), EncodeRedistributeAdd(2, 1)...))
	f.Fuzz(func(t *testing.T, data []byte) {
		r := bytes.NewReader(data)
		for i := 0; i < 16; i++ {
			if _, _, err := ReadMessage(r); err != nil {
				return
			}
		}
	})
}
