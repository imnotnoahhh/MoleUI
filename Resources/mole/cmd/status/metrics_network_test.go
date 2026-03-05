package main

import (
	"strings"
	"testing"

	gopsutilnet "github.com/shirou/gopsutil/v4/net"
)

func TestCollectProxyFromEnvSupportsAllProxy(t *testing.T) {
	env := map[string]string{
		"ALL_PROXY": "socks5://127.0.0.1:7890",
	}
	getenv := func(key string) string {
		return env[key]
	}

	got := collectProxyFromEnv(getenv)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "SOCKS" {
		t.Fatalf("expected SOCKS type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:7890" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectProxyFromScutilOutputPAC(t *testing.T) {
	out := `
<dictionary> {
  ProxyAutoConfigEnable : 1
  ProxyAutoConfigURLString : http://127.0.0.1:6152/proxy.pac
}`
	got := collectProxyFromScutilOutput(out)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "PAC" {
		t.Fatalf("expected PAC type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:6152" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectProxyFromScutilOutputHTTPHostPort(t *testing.T) {
	out := `
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 7890
}`
	got := collectProxyFromScutilOutput(out)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "HTTP" {
		t.Fatalf("expected HTTP type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:7890" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectIOCountersSafelyRecoversPanic(t *testing.T) {
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		panic("boom")
	}
	t.Cleanup(func() { ioCountersFunc = original })

	stats, err := collectIOCountersSafely(true)
	if err == nil {
		t.Fatalf("expected error from panic recovery")
	}
	if !strings.Contains(err.Error(), "panic collecting network counters") {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(stats) != 0 {
		t.Fatalf("expected empty stats when panic recovered")
	}
}

func TestCollectIOCountersSafelyReturnsData(t *testing.T) {
	original := ioCountersFunc
	want := []gopsutilnet.IOCountersStat{
		{Name: "en0", BytesRecv: 1, BytesSent: 2},
	}
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return want, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	got, err := collectIOCountersSafely(true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || got[0].Name != "en0" {
		t.Fatalf("unexpected stats: %+v", got)
	}
}
