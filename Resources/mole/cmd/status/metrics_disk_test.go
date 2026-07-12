package main

import (
	"context"
	"errors"
	"testing"

	"github.com/shirou/gopsutil/v4/disk"
)

func TestShouldSkipDiskPartition(t *testing.T) {
	tests := []struct {
		name string
		part disk.PartitionStat
		want bool
	}{
		{
			name: "keep local apfs root volume",
			part: disk.PartitionStat{
				Device:     "/dev/disk3s1s1",
				Mountpoint: "/",
				Fstype:     "apfs",
			},
			want: false,
		},
		{
			name: "skip macfuse mirror mount",
			part: disk.PartitionStat{
				Device:     "kaku-local:/",
				Mountpoint: "/Users/tw93/Library/Caches/dev.kaku/sshfs/kaku-local",
				Fstype:     "macfuse",
			},
			want: true,
		},
		{
			name: "skip smb share",
			part: disk.PartitionStat{
				Device:     "//server/share",
				Mountpoint: "/Volumes/share",
				Fstype:     "smbfs",
			},
			want: true,
		},
		{
			name: "skip system volume",
			part: disk.PartitionStat{
				Device:     "/dev/disk3s5",
				Mountpoint: "/System/Volumes/Data",
				Fstype:     "apfs",
			},
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldSkipDiskPartition(tt.part); got != tt.want {
				t.Fatalf("shouldSkipDiskPartition(%+v) = %v, want %v", tt.part, got, tt.want)
			}
		})
	}
}

func TestExtractPlistUint(t *testing.T) {
	t.Run("prefers first matching key", func(t *testing.T) {
		raw := `<plist><dict>
<key>TotalSize</key><integer>1099511627776</integer>
<key>DiskSize</key><integer>2199023255552</integer>
</dict></plist>`

		got, err := extractPlistUint(raw, "TotalSize", "DiskSize")
		if err != nil {
			t.Fatalf("extractPlistUint() error = %v", err)
		}
		if got != 1099511627776 {
			t.Fatalf("extractPlistUint() = %d, want %d", got, uint64(1099511627776))
		}
	})

	t.Run("falls back to later keys", func(t *testing.T) {
		raw := `<plist><dict><key>DiskSize</key><integer>1099511627776</integer></dict></plist>`

		got, err := extractPlistUint(raw, "TotalSize", "DiskSize", "Size")
		if err != nil {
			t.Fatalf("extractPlistUint() error = %v", err)
		}
		if got != 1099511627776 {
			t.Fatalf("extractPlistUint() = %d, want %d", got, uint64(1099511627776))
		}
	})

	t.Run("returns error for malformed integer", func(t *testing.T) {
		raw := `<plist><dict><key>TotalSize</key><integer>oops</integer></dict></plist>`

		if _, err := extractPlistUint(raw, "TotalSize"); err == nil {
			t.Fatalf("extractPlistUint() expected parse error")
		}
	})
}

func TestCollectDisksFastSkipsSlowCorrections(t *testing.T) {
	origPartitions := diskPartitionsFunc
	origUsage := diskUsageFunc
	origRunCmd := runCmd
	origCommandExists := commandExists
	t.Cleanup(func() {
		diskPartitionsFunc = origPartitions
		diskUsageFunc = origUsage
		runCmd = origRunCmd
		commandExists = origCommandExists
	})

	const rawTotal = uint64(2 * 1024 * 1024 * 1024)
	const rawUsed = uint64(1024 * 1024 * 1024)
	diskPartitionsFunc = func(all bool) ([]disk.PartitionStat, error) {
		if all {
			t.Fatalf("collectDisksFast() should request physical partitions only")
		}
		return []disk.PartitionStat{
			{Device: "/dev/disk3s1s1", Mountpoint: "/", Fstype: "apfs"},
		}, nil
	}
	diskUsageFunc = func(path string) (*disk.UsageStat, error) {
		if path != "/" {
			t.Fatalf("unexpected disk usage path %q", path)
		}
		return &disk.UsageStat{
			Path:        path,
			Fstype:      "apfs",
			Total:       rawTotal,
			Used:        rawUsed,
			UsedPercent: 50,
		}, nil
	}
	commandExists = func(name string) bool {
		t.Fatalf("collectDisksFast() should not check external command %q", name)
		return false
	}
	runCmd = func(ctx context.Context, name string, args ...string) (string, error) {
		t.Fatalf("collectDisksFast() should not run external command %q", name)
		return "", errors.New("unexpected command")
	}

	got, err := collectDisksFast()
	if err != nil {
		t.Fatalf("collectDisksFast() error = %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("collectDisksFast() returned %d disks, want 1: %#v", len(got), got)
	}
	if got[0].Total != rawTotal || got[0].Used != rawUsed || got[0].UsedPercent != 50 {
		t.Fatalf("collectDisksFast() should keep raw usage, got %#v", got[0])
	}
}

func TestCorrectDiskTotalBytes(t *testing.T) {
	origRunCmd := runCmd
	origCommandExists := commandExists
	t.Cleanup(func() {
		runCmd = origRunCmd
		commandExists = origCommandExists
	})

	commandExists = func(name string) bool {
		return name == "diskutil"
	}

	t.Run("uses diskutil total when meaningfully different", func(t *testing.T) {
		runCmd = func(ctx context.Context, name string, args ...string) (string, error) {
			if name != "diskutil" {
				return "", errors.New("unexpected command")
			}
			return `<plist><dict><key>TotalSize</key><integer>1099511627776</integer></dict></plist>`, nil
		}

		got := correctDiskTotalBytes("/Volumes/Backup", 2199023255552)
		if got != 1099511627776 {
			t.Fatalf("correctDiskTotalBytes() = %d, want %d", got, uint64(1099511627776))
		}
	})

	t.Run("keeps raw total for small differences", func(t *testing.T) {
		runCmd = func(ctx context.Context, name string, args ...string) (string, error) {
			return `<plist><dict><key>TotalSize</key><integer>1000500000000</integer></dict></plist>`, nil
		}

		const rawTotal = 1000000000000
		got := correctDiskTotalBytes("/Volumes/FastSSD", rawTotal)
		if got != rawTotal {
			t.Fatalf("correctDiskTotalBytes() = %d, want %d", got, uint64(rawTotal))
		}
	})

	t.Run("keeps raw total when diskutil fails", func(t *testing.T) {
		runCmd = func(ctx context.Context, name string, args ...string) (string, error) {
			return "", errors.New("diskutil failed")
		}

		const rawTotal = 1099511627776
		got := correctDiskTotalBytes("/Volumes/FastSSD", rawTotal)
		if got != rawTotal {
			t.Fatalf("correctDiskTotalBytes() = %d, want %d", got, uint64(rawTotal))
		}
	})
}

func TestCounterDeltaClampsCounterReset(t *testing.T) {
	if got := counterDelta(150, 100); got != 50 {
		t.Fatalf("counterDelta increasing = %d, want 50", got)
	}
	if got := counterDelta(10, 100); got != 0 {
		t.Fatalf("counterDelta reset = %d, want 0", got)
	}
}
