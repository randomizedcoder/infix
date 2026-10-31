// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package iface

import (
	"encoding/json"
	"testing"
)

// iproute2 JSON (bridge vlan show, ip -j link).
func FuzzParseVLANTable(f *testing.F) {
	f.Add(`[{"ifname":"e1","vlans":[{"vlan":1,"flags":["PVID","Egress Untagged"]},{"vlan":10,"vlanEnd":20}]}]`)
	f.Fuzz(func(t *testing.T, s string) { _ = ParseVLANTable(json.RawMessage(s)) })
}

func FuzzDecodeObjects(f *testing.F) {
	f.Add(`[{"ifname":"e1","mtu":1500}]`)
	f.Add(`{"ifname":"e1"}`)
	f.Fuzz(func(t *testing.T, s string) { _ = decodeObjects(json.RawMessage(s)) })
}
