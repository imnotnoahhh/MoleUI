package main

import (
	"strings"
	"testing"
	"time"

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

func TestCollectNetworkFirstSampleReturnsZeroRateInterfaces(t *testing.T) {
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return []gopsutilnet.IOCountersStat{
			{Name: "en0", BytesRecv: 1000, BytesSent: 2000},
		}, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	c := &Collector{}
	got, err := c.collectNetwork(time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected first sample to render one interface, got %+v", got)
	}
	if got[0].RxRateMBs != 0 || got[0].TxRateMBs != 0 {
		t.Fatalf("expected first sample zero rates, got %+v", got[0])
	}
	if len(c.rxHistoryBuf.Slice()) != 1 || len(c.txHistoryBuf.Slice()) != 1 {
		t.Fatalf("expected history to be seeded on first sample")
	}
}

func TestCollectNetworkUsesPrimedCountersForInitialRates(t *testing.T) {
	original := ioCountersFunc
	calls := 0
	samples := [][]gopsutilnet.IOCountersStat{
		{{Name: "en0", BytesRecv: 1024 * 1024, BytesSent: 0}},
		{{Name: "en0", BytesRecv: 2 * 1024 * 1024, BytesSent: 512 * 1024}},
	}
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		if calls >= len(samples) {
			return samples[len(samples)-1], nil
		}
		got := samples[calls]
		calls++
		return got, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	c := NewCollector(ProcessWatchOptions{})
	got, err := c.collectNetwork(c.lastNetAt.Add(time.Second))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected one interface, got %+v", got)
	}
	if got[0].RxRateMBs != 1.0 {
		t.Fatalf("expected 1 MB/s down, got %v", got[0].RxRateMBs)
	}
	if got[0].TxRateMBs != 0.5 {
		t.Fatalf("expected 0.5 MB/s up, got %v", got[0].TxRateMBs)
	}
}

func TestCollectNetworkClampsCounterReset(t *testing.T) {
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return []gopsutilnet.IOCountersStat{
			{Name: "en0", BytesRecv: 10, BytesSent: 20},
		}, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	base := time.Now()
	c := &Collector{
		prevNet: map[string]gopsutilnet.IOCountersStat{
			"en0": {Name: "en0", BytesRecv: 1024 * 1024, BytesSent: 1024 * 1024},
		},
		lastNetAt:    base,
		rxHistoryBuf: NewRingBuffer(NetworkHistorySize),
		txHistoryBuf: NewRingBuffer(NetworkHistorySize),
	}

	got, err := c.collectNetwork(base.Add(time.Second))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected one interface, got %+v", got)
	}
	if got[0].RxRateMBs != 0 || got[0].TxRateMBs != 0 {
		t.Fatalf("expected reset counters to clamp to zero, got %+v", got[0])
	}
}
