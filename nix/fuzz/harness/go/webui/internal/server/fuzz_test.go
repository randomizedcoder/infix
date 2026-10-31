// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package server

import (
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

// FuzzSameOrigin: a request whose Origin names another host is cross-site,
// whatever else it carries, unless X-Forwarded-Host claims that host.
func FuzzSameOrigin(f *testing.F) {
	f.Add("device.local", "https://device.local", "", "")
	f.Add("device.local", "https://evil.example", "", "")
	f.Add("device.local", "", "https://evil.example/x", "")
	f.Add("device.local", "https://evil.example", "", "evil.example")
	f.Fuzz(func(t *testing.T, host, origin, referer, xfh string) {
		if host == "" || strings.ContainsAny(host, "/?#@ \t\r\n") {
			return
		}
		r := httptest.NewRequest("POST", "/", nil)
		r.Host = host
		if origin != "" {
			r.Header.Set("Origin", origin)
		}
		if referer != "" {
			r.Header.Set("Referer", referer)
		}
		if xfh != "" {
			r.Header.Set("X-Forwarded-Host", xfh)
		}
		got := sameOrigin(r)
		if r.Header.Get("X-Forwarded-Host") != "" || r.Header.Get("Origin") == "" {
			return
		}
		u, err := url.Parse(r.Header.Get("Origin"))
		if got && (err != nil || !strings.EqualFold(u.Host, host)) {
			t.Fatalf("Origin %q accepted for Host %q", r.Header.Get("Origin"), host)
		}
	})
}

func FuzzValidCSRF(f *testing.F) {
	f.Add("tok", "tok")
	f.Add("tok", "")
	f.Fuzz(func(t *testing.T, token, sent string) {
		r := httptest.NewRequest("POST", "/", nil)
		if sent != "" {
			r.Header.Set("X-CSRF-Token", sent)
		}
		got := validCSRF(r, token)
		want := token != "" && r.Header.Get("X-CSRF-Token") == token
		if got != want {
			t.Fatalf("validCSRF(token=%q, header=%q) = %v", token, r.Header.Get("X-CSRF-Token"), got)
		}
	})
}

// FuzzIsPublicPath: only the login page and the static assets skip the session check.
func FuzzIsPublicPath(f *testing.F) {
	f.Add("/login")
	f.Add("/assets/app.js")
	f.Add("/assets/../configure")
	f.Fuzz(func(t *testing.T, p string) {
		if isPublicPath(p) && p != "/login" && !strings.HasPrefix(p, "/assets/") {
			t.Fatalf("%q is public", p)
		}
	})
}
