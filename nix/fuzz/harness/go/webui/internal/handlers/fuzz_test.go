// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package handlers

import (
	"net/url"
	"strings"
	"testing"
)

// FuzzDiagCommand: for a target validTarget accepts, the tool gets it as its
// last argument and no argument made from the query is an option.
func FuzzDiagCommand(f *testing.F) {
	f.Add("ping", "192.0.2.1", "4", "e1", "count=3&size=56")
	f.Add("nmap", "host.example", "6", "", "scan=services")
	f.Add("mtr", "-oX", "auto", "", "count=-1")
	f.Fuzz(func(t *testing.T, tool, target, family, iface, query string) {
		if !validTarget(target) {
			return
		}
		q, err := url.ParseQuery(query)
		if err != nil {
			return
		}
		_, args, ok := diagCommand(tool, target, family, iface, q)
		if !ok {
			return
		}
		if args[len(args)-1] != target {
			t.Fatalf("target %q is not the last argument: %q", target, args)
		}
		for i, a := range args[:len(args)-1] {
			if strings.HasPrefix(a, "-") {
				continue
			}
			if i > 0 && strings.HasPrefix(args[i-1], "-") {
				continue // an option's value
			}
			t.Fatalf("stray operand %q before the target: %q", a, args)
		}
	})
}

func FuzzValidTarget(f *testing.F) {
	f.Add("192.0.2.1")
	f.Add("-oX")
	f.Fuzz(func(t *testing.T, s string) {
		if validTarget(s) && (strings.HasPrefix(s, "-") || strings.ContainsAny(s, " \t\n\r\x00")) {
			t.Fatalf("validTarget accepts %q", s)
		}
	})
}
