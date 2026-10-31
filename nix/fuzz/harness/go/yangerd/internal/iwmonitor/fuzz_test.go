// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package iwmonitor

import "testing"

// wpa_supplicant's escaped SSID: any 32 bytes a neighbour advertises.
func FuzzDecodeWPASSID(f *testing.F) {
	f.Add(`infix`)
	f.Add(`\xe2\x9c\x93\"\\`)
	f.Fuzz(func(t *testing.T, s string) { _ = decodeWPASSID(s) })
}
