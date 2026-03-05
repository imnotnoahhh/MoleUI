package main

import (
	"os"
	"testing"
)

func TestShouldUseJSONOutput_ForceFlag(t *testing.T) {
	if !shouldUseJSONOutput(true, nil) {
		t.Fatalf("expected force JSON flag to enable JSON mode")
	}
}

func TestShouldUseJSONOutput_NilStdout(t *testing.T) {
	if shouldUseJSONOutput(false, nil) {
		t.Fatalf("expected nil stdout to keep TUI mode")
	}
}

func TestShouldUseJSONOutput_NonTTYPipe(t *testing.T) {
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("create pipe: %v", err)
	}
	defer reader.Close()
	defer writer.Close()

	if !shouldUseJSONOutput(false, writer) {
		t.Fatalf("expected pipe stdout to use JSON mode")
	}
}

func TestShouldUseJSONOutput_NonTTYFile(t *testing.T) {
	tmpFile, err := os.CreateTemp("", "mole-status-stdout-*.txt")
	if err != nil {
		t.Fatalf("create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name())
	defer tmpFile.Close()

	if !shouldUseJSONOutput(false, tmpFile) {
		t.Fatalf("expected file stdout to use JSON mode")
	}
}
