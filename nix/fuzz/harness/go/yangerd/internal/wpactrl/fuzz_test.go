// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package wpactrl

import "testing"

// wpa_supplicant and hostapd replies; SSIDs and station data come from the air.
func FuzzParseKV(f *testing.F) {
	f.Add("bssid=00:11:22:33:44:55\nssid=infix\nwpa_state=COMPLETED\n")
	f.Fuzz(func(t *testing.T, s string) { _ = ParseKV(s) })
}

func FuzzParseScanResults(f *testing.F) {
	f.Add("bssid / frequency / signal level / flags / ssid\n" +
		"00:11:22:33:44:55\t2412\t-40\t[WPA2-PSK-CCMP][ESS]\tinfix\n")
	f.Fuzz(func(t *testing.T, s string) { _ = ParseScanResults(s) })
}

func FuzzParseStationResp(f *testing.F) {
	f.Add("00:11:22:33:44:55\nflags=[AUTH][ASSOC]\nrx_bytes=10\nsignal=-40\n")
	f.Fuzz(func(t *testing.T, s string) { _ = ParseStationResp(s) })
}

func FuzzParseEvent(f *testing.F) {
	f.Add("<3>CTRL-EVENT-CONNECTED - Connection to 00:11:22:33:44:55 completed")
	f.Add("<3>AP-STA-CONNECTED 00:11:22:33:44:55")
	f.Fuzz(func(t *testing.T, s string) { _, _ = ParseEvent(s) })
}
