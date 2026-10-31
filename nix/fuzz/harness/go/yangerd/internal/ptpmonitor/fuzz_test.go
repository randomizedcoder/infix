// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package ptpmonitor

import "testing"

// PTP management responses from ptp4l's UDS socket.
func FuzzDecodePacket(f *testing.F) {
	f.Add(make([]byte, 54))
	f.Fuzz(func(t *testing.T, data []byte) { _, _ = decodePacket(data) })
}
