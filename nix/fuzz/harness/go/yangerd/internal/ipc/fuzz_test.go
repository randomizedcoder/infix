// nix/fuzz/harness/go: copied into the module at build time (nix/fuzz/go.nix).

package ipc

import (
	"bytes"
	"testing"
)

func frame(payload []byte) []byte {
	var b bytes.Buffer
	_ = WriteFrame(&b, payload)
	return b.Bytes()
}

// FuzzReadFrame: what yangerd reads from a client socket.
func FuzzReadFrame(f *testing.F) {
	f.Add(frame([]byte(`{"path":"/ietf-interfaces:interfaces"}`)))
	f.Add([]byte{Version, 0xff, 0xff, 0xff, 0xff})
	f.Fuzz(func(t *testing.T, data []byte) {
		buf, err := ReadFrame(bytes.NewReader(data))
		if err == nil && len(buf) > MaxPayload {
			t.Fatalf("frame of %d bytes exceeds MaxPayload", len(buf))
		}
	})
}

func FuzzReadRequest(f *testing.F) {
	f.Add(frame([]byte(`{"path":"/ietf-interfaces:interfaces"}`)))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = ReadRequest(bytes.NewReader(data))
	})
}

func FuzzReadResponse(f *testing.F) {
	f.Add(append(frame([]byte(`{"status":"ok","raw":true}`)), frame([]byte(`{}`))...))
	f.Add(frame([]byte(`{"status":"error","message":"x"}`)))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = ReadResponse(bytes.NewReader(data))
	})
}
