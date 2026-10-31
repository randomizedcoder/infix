// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package lldpmonitor

import (
	"encoding/json"
	"testing"
)

// lldpctl JSON; the values are what a neighbour put in its LLDPDUs.
func FuzzParseID(f *testing.F) {
	f.Add(`{"type":"mac","value":"00:11:22:33:44:55"}`)
	f.Add(`[{"type":"local","value":"x"}]`)
	f.Fuzz(func(t *testing.T, s string) { _, _ = parseID(json.RawMessage(s)) })
}

func FuzzParseAge(f *testing.F) {
	f.Add("0 day, 00:01:02")
	f.Add("12 days, 23:59:59")
	f.Fuzz(func(t *testing.T, s string) { _ = parseAge(s) })
}
