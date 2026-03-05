package main

import (
	"strings"
	"testing"
)

func TestCalculateHealthScorePerfect(t *testing.T) {
	score, msg := calculateHealthScore(
		CPUStatus{Usage: 10},
		MemoryStatus{UsedPercent: 20, Pressure: "normal"},
		[]DiskStatus{{UsedPercent: 30}},
		DiskIOStatus{ReadRate: 5, WriteRate: 5},
		ThermalStatus{CPUTemp: 40},
	)

	if score != 100 {
		t.Fatalf("expected perfect score 100, got %d", score)
	}
	if msg != "Excellent" {
		t.Fatalf("unexpected message %q", msg)
	}
}

func TestCalculateHealthScoreDetectsIssues(t *testing.T) {
	score, msg := calculateHealthScore(
		CPUStatus{Usage: 95},
		MemoryStatus{UsedPercent: 90, Pressure: "critical"},
		[]DiskStatus{{UsedPercent: 95}},
		DiskIOStatus{ReadRate: 120, WriteRate: 80},
		ThermalStatus{CPUTemp: 90},
	)

	if score >= 40 {
		t.Fatalf("expected heavy penalties bringing score down, got %d", score)
	}
	if msg == "Excellent" {
		t.Fatalf("expected message to include issues, got %q", msg)
	}
	if !strings.Contains(msg, "High CPU") {
		t.Fatalf("message should mention CPU issue: %q", msg)
	}
	if !strings.Contains(msg, "Disk Almost Full") {
		t.Fatalf("message should mention disk issue: %q", msg)
	}
}

func TestFormatUptime(t *testing.T) {
	if got := formatUptime(65); got != "1m" {
		t.Fatalf("expected 1m, got %s", got)
	}
	if got := formatUptime(3600 + 120); got != "1h 2m" {
		t.Fatalf("expected \"1h 2m\", got %s", got)
	}
	if got := formatUptime(86400*2 + 3600*3 + 60*5); got != "2d 3h" {
		t.Fatalf("expected \"2d 3h\", got %s", got)
	}
}

func TestColorizeTempThresholds(t *testing.T) {
	tests := []struct {
		temp     float64
		expected string
	}{
		{temp: 30.0, expected: "30.0"}, // Normal - should use okStyle (green)
		{temp: 55.9, expected: "55.9"}, // Just below warning threshold
		{temp: 56.0, expected: "56.0"}, // Warning threshold - should use warnStyle (yellow)
		{temp: 65.0, expected: "65.0"}, // Mid warning range
		{temp: 75.9, expected: "75.9"}, // Just below danger threshold
		{temp: 76.0, expected: "76.0"}, // Danger threshold - should use dangerStyle (red)
		{temp: 90.0, expected: "90.0"}, // High temperature
		{temp: 0.0, expected: "0.0"},   // Edge case: zero
	}

	for _, tt := range tests {
		result := colorizeTemp(tt.temp)
		// Check that result contains the formatted temperature value
		if !strings.Contains(result, tt.expected) {
			t.Errorf("colorizeTemp(%.1f) = %q, should contain %q", tt.temp, result, tt.expected)
		}
		// Verify output is not empty and contains the temperature
		if result == "" {
			t.Errorf("colorizeTemp(%.1f) returned empty string", tt.temp)
		}
	}
}

func TestColorizeTempStyleRanges(t *testing.T) {
	normalTemp := colorizeTemp(40.0)
	warningTemp := colorizeTemp(65.0)
	dangerTemp := colorizeTemp(85.0)

	if normalTemp == "" || warningTemp == "" || dangerTemp == "" {
		t.Fatal("colorizeTemp should not return empty strings")
	}

	if !strings.Contains(normalTemp, "40.0") {
		t.Errorf("normal temp should contain '40.0', got: %s", normalTemp)
	}
	if !strings.Contains(warningTemp, "65.0") {
		t.Errorf("warning temp should contain '65.0', got: %s", warningTemp)
	}
	if !strings.Contains(dangerTemp, "85.0") {
		t.Errorf("danger temp should contain '85.0', got: %s", dangerTemp)
	}
}

func TestCalculateHealthScoreEdgeCases(t *testing.T) {
	tests := []struct {
		name    string
		cpu     CPUStatus
		mem     MemoryStatus
		disks   []DiskStatus
		diskIO  DiskIOStatus
		thermal ThermalStatus
		wantMin int
		wantMax int
	}{
		{
			name:    "all metrics at normal threshold",
			cpu:     CPUStatus{Usage: 30.0},
			mem:     MemoryStatus{UsedPercent: 50.0},
			disks:   []DiskStatus{{UsedPercent: 70.0}},
			diskIO:  DiskIOStatus{ReadRate: 25.0, WriteRate: 25.0},
			thermal: ThermalStatus{CPUTemp: 60.0},
			wantMin: 95,
			wantMax: 100,
		},
		{
			name:    "memory pressure warning only",
			cpu:     CPUStatus{Usage: 10.0},
			mem:     MemoryStatus{UsedPercent: 40.0, Pressure: "warn"},
			disks:   []DiskStatus{{UsedPercent: 40.0}},
			diskIO:  DiskIOStatus{ReadRate: 5.0, WriteRate: 5.0},
			thermal: ThermalStatus{CPUTemp: 40.0},
			wantMin: 90,
			wantMax: 100,
		},
		{
			name:    "empty disks array",
			cpu:     CPUStatus{Usage: 10.0},
			mem:     MemoryStatus{UsedPercent: 30.0},
			disks:   []DiskStatus{},
			diskIO:  DiskIOStatus{ReadRate: 5.0, WriteRate: 5.0},
			thermal: ThermalStatus{CPUTemp: 40.0},
			wantMin: 95,
			wantMax: 100,
		},
		{
			name:    "zero thermal data",
			cpu:     CPUStatus{Usage: 10.0},
			mem:     MemoryStatus{UsedPercent: 30.0},
			disks:   []DiskStatus{{UsedPercent: 40.0}},
			diskIO:  DiskIOStatus{ReadRate: 5.0, WriteRate: 5.0},
			thermal: ThermalStatus{CPUTemp: 0},
			wantMin: 95,
			wantMax: 100,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			score, _ := calculateHealthScore(tt.cpu, tt.mem, tt.disks, tt.diskIO, tt.thermal)
			if score < tt.wantMin || score > tt.wantMax {
				t.Errorf("calculateHealthScore() = %d, want range [%d, %d]", score, tt.wantMin, tt.wantMax)
			}
		})
	}
}

func TestFormatUptimeEdgeCases(t *testing.T) {
	tests := []struct {
		name string
		secs uint64
		want string
	}{
		{"zero seconds", 0, "0m"},
		{"59 seconds", 59, "0m"},
		{"one minute exact", 60, "1m"},
		{"59 minutes 59 seconds", 3599, "59m"},
		{"one hour exact", 3600, "1h 0m"},
		{"one day exact", 86400, "1d 0h"},
		{"one day one hour", 90000, "1d 1h"},
		{"multiple days no hours", 172800, "2d 0h"},
		{"large uptime", 31536000, "365d 0h"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := formatUptime(tt.secs)
			if got != tt.want {
				t.Errorf("formatUptime(%d) = %q, want %q", tt.secs, got, tt.want)
			}
		})
	}
}
