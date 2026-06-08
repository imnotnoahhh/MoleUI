//go:build darwin

package main

import (
	"sort"
	"sync/atomic"
	"time"
)

type dirEntry struct {
	Name       string
	Path       string
	Size       int64
	IsDir      bool
	LastAccess time.Time
}

type fileEntry struct {
	Name string
	Path string
	Size int64
}

type scanResult struct {
	Entries    []dirEntry
	LargeFiles []fileEntry
	TotalSize  int64
	TotalFiles int64
	// dedupedHardlink is true when a hardlinked file in this subtree was
	// counted as zero because another link was seen earlier in the same
	// scan. Such a result is scan-order dependent and must not be written
	// to the on-disk cache. In-memory only; never serialized to cacheEntry.
	dedupedHardlink bool
}

type cacheEntry struct {
	Entries      []dirEntry
	LargeFiles   []fileEntry
	TotalSize    int64
	TotalFiles   int64
	ModTime      time.Time
	ScanTime     time.Time
	NeedsRefresh bool
	// SchemaVersion guards against reusing cache written by an older binary
	// with different sizing semantics. Entries not at cacheSchemaVersion are
	// rejected on load. Old caches decode this as 0.
	SchemaVersion int
}

type historyEntry struct {
	Path          string
	Entries       []dirEntry
	LargeFiles    []fileEntry
	TotalSize     int64
	TotalFiles    int64
	Selected      int
	EntryOffset   int
	LargeSelected int
	LargeOffset   int
	NeedsRefresh  bool
	IsOverview    bool
}

type scanResultMsg struct {
	path   string
	result scanResult
	err    error
	stale  bool
}

type overviewSizeMsg struct {
	Path  string
	Index int
	Size  int64
	Err   error
}

type tickMsg time.Time

type deleteProgressMsg struct {
	done  bool
	err   error
	count int64
	path  string
}

type model struct {
	path                string
	history             []historyEntry
	entries             []dirEntry
	largeFiles          []fileEntry
	selected            int
	offset              int
	status              string
	totalSize           int64
	scanning            bool
	spinner             int
	filesScanned        *int64
	dirsScanned         *int64
	bytesScanned        *int64
	currentPath         *atomic.Value
	showLargeFiles      bool
	isOverview          bool
	deleteConfirm       bool
	deleteTarget        *dirEntry
	deleting            bool
	deleteCount         *int64
	cache               map[string]historyEntry
	largeSelected       int
	largeOffset         int
	overviewSizeCache   map[string]int64
	overviewScanning    bool
	overviewScanningSet map[string]bool // Track which paths are currently being scanned
	width               int             // Terminal width
	height              int             // Terminal height
	multiSelected       map[string]bool // Track multi-selected items by path (safer than index)
	largeMultiSelected  map[string]bool // Track multi-selected large files by path (safer than index)
	totalFiles          int64           // Total files found in current/last scan
	lastTotalFiles      int64           // Total files from previous scan (for progress bar)
	diskFree            int64           // Free disk space for the analyzed volume
	viewNeedsRefresh    bool
}

func (m model) inOverviewMode() bool {
	return m.isOverview && m.path == "/"
}

func (m *model) hydrateOverviewEntries() {
	m.entries = createOverviewEntries()
	if m.overviewSizeCache == nil {
		m.overviewSizeCache = make(map[string]int64)
	}
	for i := range m.entries {
		if size, ok := m.overviewSizeCache[m.entries[i].Path]; ok {
			m.entries[i].Size = size
			continue
		}
		if size, err := loadOverviewCachedSize(m.entries[i].Path); err == nil {
			m.entries[i].Size = size
			m.overviewSizeCache[m.entries[i].Path] = size
		}
	}
	m.totalSize = sumKnownEntrySizes(m.entries)
}

func (m *model) sortOverviewEntriesBySize() {
	// Stable sort by size.
	sort.SliceStable(m.entries, func(i, j int) bool {
		return m.entries[i].Size > m.entries[j].Size
	})
}

func (m *model) getScanProgress() (files, dirs, bytes int64) {
	if m.filesScanned != nil {
		files = atomic.LoadInt64(m.filesScanned)
	}
	if m.dirsScanned != nil {
		dirs = atomic.LoadInt64(m.dirsScanned)
	}
	if m.bytesScanned != nil {
		bytes = atomic.LoadInt64(m.bytesScanned)
	}
	return
}

func (m *model) clampEntrySelection() {
	if len(m.entries) == 0 {
		m.selected = 0
		m.offset = 0
		return
	}
	if m.selected >= len(m.entries) {
		m.selected = len(m.entries) - 1
	}
	if m.selected < 0 {
		m.selected = 0
	}
	viewport := calculateViewport(m.height, false)
	maxOffset := max(len(m.entries)-viewport, 0)
	if m.offset > maxOffset {
		m.offset = maxOffset
	}
	if m.selected < m.offset {
		m.offset = m.selected
	}
	if m.selected >= m.offset+viewport {
		m.offset = m.selected - viewport + 1
	}
}

func (m *model) clampLargeSelection() {
	if len(m.largeFiles) == 0 {
		m.largeSelected = 0
		m.largeOffset = 0
		return
	}
	if m.largeSelected >= len(m.largeFiles) {
		m.largeSelected = len(m.largeFiles) - 1
	}
	if m.largeSelected < 0 {
		m.largeSelected = 0
	}
	viewport := calculateViewport(m.height, true)
	maxOffset := max(len(m.largeFiles)-viewport, 0)
	if m.largeOffset > maxOffset {
		m.largeOffset = maxOffset
	}
	if m.largeSelected < m.largeOffset {
		m.largeOffset = m.largeSelected
	}
	if m.largeSelected >= m.largeOffset+viewport {
		m.largeOffset = m.largeSelected - viewport + 1
	}
}

func (m *model) removePathFromView(path string) {
	if path == "" {
		return
	}

	var removedSize int64
	for i, entry := range m.entries {
		if entry.Path == path {
			if entry.Size > 0 {
				removedSize = entry.Size
			}
			m.entries = append(m.entries[:i], m.entries[i+1:]...)
			break
		}
	}

	for i := 0; i < len(m.largeFiles); i++ {
		if m.largeFiles[i].Path == path {
			m.largeFiles = append(m.largeFiles[:i], m.largeFiles[i+1:]...)
			break
		}
	}

	if removedSize > 0 {
		if removedSize > m.totalSize {
			m.totalSize = 0
		} else {
			m.totalSize -= removedSize
		}
		m.clampEntrySelection()
	}
	m.clampLargeSelection()
}
