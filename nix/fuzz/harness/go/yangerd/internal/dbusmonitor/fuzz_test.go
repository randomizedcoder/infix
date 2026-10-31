// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package dbusmonitor

import "testing"

// dnsmasq's lease file; hostnames and client ids come from DHCP clients.
func FuzzParseDnsmasqLeases(f *testing.F) {
	f.Add("1730000000 00:11:22:33:44:55 192.168.0.10 host 01:00:11:22:33:44:55\n")
	f.Add("duid 00:01:00:01\n1730000000 1234 2001:db8::10 host 00:01:00:01\n")
	f.Fuzz(func(t *testing.T, s string) { _ = parseDnsmasqLeases(s) })
}
