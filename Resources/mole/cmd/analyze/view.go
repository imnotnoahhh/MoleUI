//go:build darwin

package main

import (
	"fmt"
	"strings"
	"sync/atomic"
)

// View renders the TUI.
func (m model) View() string {
	var b strings.Builder
	fmt.Fprintln(&b)

	// A warm cache already loaded for the current path keeps rendering while the
	// background refresh runs, instead of blanking to a scan-only screen. Fresh
	// scans (no cached entries yet) still fall back to the scan-only view.
	showingCachedView := m.scanning && !m.inOverviewMode() && m.viewNeedsRefresh && len(m.entries) > 0
	showingLiveScanView := m.scanning && !m.inOverviewMode() && len(m.entries) > 0 &&
		(m.liveScanEvents != nil || len(m.liveScanningPaths) > 0)

	if m.inOverviewMode() {
		freeLabel := ""
		if m.diskFree > 0 {
			freeLabel = fmt.Sprintf("  %s(%s free)%s", colorGray, humanizeBytes(m.diskFree), colorReset)
		}
		fmt.Fprintf(&b, "%sAnalyze Disk%s%s\n", colorPurpleBold, colorReset, freeLabel)
		if m.overviewScanning {
			if allOverviewEntriesPending(m.entries) {
				fmt.Fprintf(&b, "%sSelect a location to explore:%s  ", colorGray, colorReset)
				fmt.Fprintf(&b, "%s%s%s%s Analyzing disk usage...\n\n",
					colorCyan, colorBold, spinnerFrames[m.spinner], colorReset)
			} else {
				fmt.Fprintf(&b, "%sSelect a location to explore:%s  ", colorGray, colorReset)
				fmt.Fprintf(&b, "%s%s%s%s %s\n\n", colorCyan, colorBold, spinnerFrames[m.spinner], colorReset, m.status)
			}
		} else {
			if hasPendingOverviewEntries(m.entries) {
				fmt.Fprintf(&b, "%sSelect a location to explore:%s  ", colorGray, colorReset)
				fmt.Fprintf(&b, "%s%s%s%s %s\n\n", colorCyan, colorBold, spinnerFrames[m.spinner], colorReset, m.status)
			} else {
				fmt.Fprintf(&b, "%sSelect a location to explore:%s\n\n", colorGray, colorReset)
			}
		}
	} else {
		fmt.Fprintf(&b, "%sAnalyze Disk%s  %s%s%s", colorPurpleBold, colorReset, colorGray, displayPath(m.path), colorReset)
		if !m.scanning || m.totalSize > 0 {
			fmt.Fprintf(&b, "  |  Total: %s", humanizeBytes(m.totalSize))
		}
		fmt.Fprintf(&b, "\n\n")
	}

	if m.deleting {
		count := int64(0)
		if m.deleteCount != nil {
			count = atomic.LoadInt64(m.deleteCount)
		}

		fmt.Fprintf(&b, "%s%s%s%s Deleting: %s%s items%s removed, please wait...\n",
			colorCyan, colorBold,
			spinnerFrames[m.spinner],
			colorReset,
			colorYellow, formatNumber(count), colorReset)

		return b.String()
	}

	if m.scanning {
		filesScanned, dirsScanned, bytesScanned := m.getScanProgress()

		progressPrefix := ""
		if m.lastTotalFiles > 0 {
			percent := float64(filesScanned) / float64(m.lastTotalFiles) * 100
			// Cap at 100% generally
			if percent > 100 {
				percent = 100
			}
			// While strictly scanning, cap at 99% to avoid "100% but still working" confusion
			if m.scanning && percent >= 100 {
				percent = 99
			}
			progressPrefix = fmt.Sprintf(" %s%.0f%%%s", colorCyan, percent, colorReset)
		}

		fmt.Fprintf(&b, "%s%s%s%s Scanning%s: %s%s files%s, %s%s dirs%s, %s%s%s\n",
			colorCyan, colorBold,
			spinnerFrames[m.spinner],
			colorReset,
			progressPrefix,
			colorYellow, formatNumber(filesScanned), colorReset,
			colorYellow, formatNumber(dirsScanned), colorReset,
			colorGreen, humanizeBytes(bytesScanned), colorReset)

		if m.currentPath != nil {
			currentPath, _ := m.currentPath.Load().(string)
			if currentPath != "" {
				shortPath := displayPath(currentPath)
				shortPath = truncateMiddle(shortPath, 50)
				fmt.Fprintf(&b, "%s%s%s\n", colorGray, shortPath, colorReset)
			}
		}

		if !showingCachedView && !showingLiveScanView {
			return b.String()
		}
		if showingCachedView {
			fmt.Fprintf(&b, "%sShowing cached results while refreshing...%s\n\n", colorGray, colorReset)
		} else {
			fmt.Fprintln(&b)
		}
	}

	if m.showLargeFiles {
		if m.largeFiltering || m.largeFilter != "" {
			cursor := ""
			if m.largeFiltering {
				cursor = "▌"
			}
			fmt.Fprintf(&b, "  %sFilter:%s %s%s  %s(%d matches)%s\n\n",
				colorCyan, colorReset, m.largeFilter, cursor,
				colorGray, len(m.largeFiles), colorReset)
		}
		if len(m.largeFiles) == 0 {
			if m.largeFilter != "" {
				fmt.Fprintf(&b, "  No matches for %q\n", m.largeFilter)
			} else {
				fmt.Fprintln(&b, "  No large files found")
			}
		} else {
			viewport := calculateViewport(m.height, true)
			start := max(m.largeOffset, 0)
			end := min(start+viewport, len(m.largeFiles))
			maxLargeSize := maxLargeFileSize(m.largeFiles)
			nameWidth := calculateNameWidth(m.width)
			for idx := start; idx < end; idx++ {
				file := m.largeFiles[idx]
				shortPath := displayPath(file.Path)
				shortPath = truncateMiddle(shortPath, nameWidth)
				paddedPath := padName(shortPath, nameWidth)
				entryPrefix := "   "
				nameColor := ""
				sizeColor := colorGray
				numColor := ""

				isMultiSelected := m.largeMultiSelected != nil && m.largeMultiSelected[file.Path]
				selectIcon := "○"
				if isMultiSelected {
					selectIcon = fmt.Sprintf("%s●%s", colorGreen, colorReset)
					nameColor = colorGreen
				}

				if idx == m.largeSelected {
					entryPrefix = fmt.Sprintf(" %s%s▶%s ", colorCyan, colorBold, colorReset)
					if !isMultiSelected {
						nameColor = colorCyan
					}
					sizeColor = colorCyan
					numColor = colorCyan
				}
				size := humanizeBytes(file.Size)
				bar := coloredProgressBar(file.Size, maxLargeSize, 0)
				fmt.Fprintf(&b, "%s%s %s%2d.%s %s  |  📄 %s%s%s  %s%10s%s\n",
					entryPrefix, selectIcon, numColor, idx+1, colorReset, bar, nameColor, paddedPath, colorReset, sizeColor, size, colorReset)
			}
		}
	} else {
		if !m.inOverviewMode() && (m.entryFiltering || m.entryFilter != "") {
			cursor := ""
			if m.entryFiltering {
				cursor = "▌"
			}
			fmt.Fprintf(&b, "  %sFilter:%s %s%s  %s(%d matches)%s\n\n",
				colorCyan, colorReset, m.entryFilter, cursor,
				colorGray, len(m.entries), colorReset)
		}
		if len(m.entries) == 0 {
			if !m.inOverviewMode() && m.entryFilter != "" {
				fmt.Fprintf(&b, "  No matches for %q\n", m.entryFilter)
			} else {
				fmt.Fprintln(&b, "  Empty directory")
			}
		} else {
			if m.inOverviewMode() {
				maxSize := maxDirEntrySize(m.entries)
				totalSize := m.totalSize
				// Overview labels are short; fixed width keeps layout stable.
				nameWidth := 22
				displayNum := 0
				for idx, entry := range m.entries {
					sizeVal := entry.Size
					// Hide entries that have been scanned and are empty (standard dirs
					// are never 0 bytes; only insight dirs in unused tool paths are).
					if sizeVal == 0 {
						continue
					}
					barValue := max(sizeVal, 0)
					var percent float64
					if totalSize > 0 && sizeVal >= 0 {
						percent = float64(sizeVal) / float64(totalSize) * 100
					} else {
						percent = 0
					}
					percentStr := formatPercent(percent, totalSize > 0 && sizeVal >= 0)
					bar := coloredProgressBar(barValue, maxSize, percent)
					sizeText := "pending.."
					if sizeVal >= 0 {
						sizeText = humanizeBytes(sizeVal)
					}
					sizeColor := colorGray
					if sizeVal >= 0 && totalSize > 0 {
						sizeColor = sizeColorForPercent(percent)
					}
					entryPrefix := "   "
					name := trimNameWithWidth(entry.Name, nameWidth)
					paddedName := padName(name, nameWidth)
					nameSegment := paddedName
					numColor := ""
					percentColor := ""
					if idx == m.selected {
						entryPrefix = fmt.Sprintf(" %s%s▶%s ", colorCyan, colorBold, colorReset)
						nameSegment = fmt.Sprintf("%s%s%s", colorCyan, paddedName, colorReset)
						numColor = colorCyan
						percentColor = colorCyan
						sizeColor = colorCyan
					}
					displayNum++
					displayIndex := displayNum

					// Keep the overview text-only. Emoji width and baselines vary
					// across terminals, while every row has the same navigation.
					hintLabel := ""
					if unusedTime := formatUnusedTime(entry.LastAccess); unusedTime != "" {
						hintLabel = fmt.Sprintf("%s%s%s", colorGray, unusedTime, colorReset)
					}

					if hintLabel == "" {
						fmt.Fprintf(&b, "%s%s%2d.%s %s %s%s%s  |  %s %s%10s%s\n",
							entryPrefix, numColor, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							nameSegment, sizeColor, sizeText, colorReset)
					} else {
						fmt.Fprintf(&b, "%s%s%2d.%s %s %s%s%s  |  %s %s%10s%s  %s\n",
							entryPrefix, numColor, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							nameSegment, sizeColor, sizeText, colorReset, hintLabel)
					}
				}
			} else {
				maxSize := maxDirEntrySize(m.entries)

				viewport := calculateViewport(m.height, false)
				nameWidth := calculateNameWidth(m.width)
				start := max(m.offset, 0)
				end := min(start+viewport, len(m.entries))

				for idx := start; idx < end; idx++ {
					entry := m.entries[idx]
					icon := "📄"
					if entry.IsDir {
						icon = "📁"
					}
					name := trimNameWithWidth(entry.Name, nameWidth)
					paddedName := padName(name, nameWidth)

					sizeValue := max(entry.Size, 0)
					percent := 0.0
					if m.totalSize > 0 && entry.Size >= 0 {
						percent = float64(entry.Size) / float64(m.totalSize) * 100
					}
					percentStr := formatPercent(percent, entry.Size >= 0 && m.totalSize > 0)

					bar := coloredProgressBar(sizeValue, maxSize, percent)

					sizeColor := sizeColorForPercent(percent)
					size := humanizeBytes(entry.Size)
					if entry.Size < 0 {
						size = fmt.Sprintf("%s %s", spinnerFrames[m.spinner], "scanning")
						sizeColor = colorCyan
					}

					isMultiSelected := m.multiSelected != nil && m.multiSelected[entry.Path]
					selectIcon := "○"
					nameColor := ""
					if isMultiSelected {
						selectIcon = fmt.Sprintf("%s●%s", colorGreen, colorReset)
						nameColor = colorGreen
					}

					entryPrefix := "   "
					nameSegment := fmt.Sprintf("%s %s", icon, paddedName)
					if nameColor != "" {
						nameSegment = fmt.Sprintf("%s%s %s%s", nameColor, icon, paddedName, colorReset)
					}
					numColor := ""
					percentColor := ""
					if idx == m.selected {
						entryPrefix = fmt.Sprintf(" %s%s▶%s ", colorCyan, colorBold, colorReset)
						if !isMultiSelected {
							nameSegment = fmt.Sprintf("%s%s %s%s", colorCyan, icon, paddedName, colorReset)
						}
						numColor = colorCyan
						percentColor = colorCyan
						sizeColor = colorCyan
					}

					displayIndex := idx + 1

					hintLabel := entryHintLabel(entry)
					activityMarker := "|"
					if entry.IsDir && m.liveScanningPaths != nil && m.liveScanningPaths[entry.Path] {
						activityMarker = fmt.Sprintf("%s%s%s%s", colorCyan, colorBold, spinnerFrames[m.spinner], colorReset)
					}

					if hintLabel == "" {
						fmt.Fprintf(&b, "%s%s %s%2d.%s %s %s%s%s  %s  %s %s%10s%s\n",
							entryPrefix, selectIcon, numColor, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							activityMarker, nameSegment, sizeColor, size, colorReset)
					} else {
						fmt.Fprintf(&b, "%s%s %s%2d.%s %s %s%s%s  %s  %s %s%10s%s  %s\n",
							entryPrefix, selectIcon, numColor, displayIndex, colorReset, bar, percentColor, percentStr, colorReset,
							activityMarker, nameSegment, sizeColor, size, colorReset, hintLabel)
					}
				}
			}
		}
	}

	fmt.Fprintln(&b)
	if m.inOverviewMode() {
		if len(m.history) > 0 {
			fmt.Fprintf(&b, "%s↑↓←→ | Enter | R Refresh | O Open | P Preview | F File | Esc Back | Q/Ctrl+C Quit%s\n", colorGray, colorReset)
		} else {
			fmt.Fprintf(&b, "%s↑↓→ | Enter | R Refresh | O Open | P Preview | F File | Esc/Q Quit%s\n", colorGray, colorReset)
		}
	} else if m.showLargeFiles {
		if m.largeFiltering {
			fmt.Fprintf(&b, "%sType to filter  |  Enter Apply  |  Esc Clear  |  Ctrl+C Quit%s\n", colorGray, colorReset)
		} else if m.largeFilter != "" {
			fmt.Fprintf(&b, "%s↑↓← | Space Select | / Edit | Esc Clear filter | O Open | P Preview | F File | ⌫ Del | Q Quit%s\n", colorGray, colorReset)
		} else {
			selectCount := len(m.largeMultiSelected)
			if selectCount > 0 {
				fmt.Fprintf(&b, "%s↑↓← | Space Select | / Filter | R Refresh | O Open | P Preview | F File | ⌫ Del %d | Esc Back | Q/Ctrl+C Quit%s\n", colorGray, selectCount, colorReset)
			} else {
				fmt.Fprintf(&b, "%s↑↓← | Space Select | / Filter | R Refresh | O Open | P Preview | F File | ⌫ Del | Esc Back | Q/Ctrl+C Quit%s\n", colorGray, colorReset)
			}
		}
	} else if m.entryFiltering {
		fmt.Fprintf(&b, "%sType to filter  |  Enter Apply  |  Esc Clear  |  Ctrl+C Quit%s\n", colorGray, colorReset)
	} else if m.entryFilter != "" {
		fmt.Fprintf(&b, "%s↑↓←→ | Enter | Space Select | / Edit | Esc Clear filter | O Open | P Preview | F File | ⌫ Del | Q Quit%s\n", colorGray, colorReset)
	} else {
		largeFileCount := len(m.largeFiles)
		selectCount := len(m.multiSelected)
		if selectCount > 0 {
			if largeFileCount > 0 {
				fmt.Fprintf(&b, "%s↑↓←→ | Space Select | Enter | / Filter | R Refresh | O Open | P Preview | F File | ⌫ Del %d | T Top %d | Esc Back | Q/Ctrl+C Quit%s\n", colorGray, selectCount, largeFileCount, colorReset)
			} else {
				fmt.Fprintf(&b, "%s↑↓←→ | Space Select | Enter | / Filter | R Refresh | O Open | P Preview | F File | ⌫ Del %d | Esc Back | Q/Ctrl+C Quit%s\n", colorGray, selectCount, colorReset)
			}
		} else {
			if largeFileCount > 0 {
				fmt.Fprintf(&b, "%s↑↓←→ | Space Select | Enter | / Filter | R Refresh | O Open | P Preview | F File | ⌫ Del | T Top %d | Esc Back | Q/Ctrl+C Quit%s\n", colorGray, largeFileCount, colorReset)
			} else {
				fmt.Fprintf(&b, "%s↑↓←→ | Space Select | Enter | / Filter | R Refresh | O Open | P Preview | F File | ⌫ Del | Esc Back | Q/Ctrl+C Quit%s\n", colorGray, colorReset)
			}
		}
	}
	if m.deleteConfirm && m.deleteTarget != nil {
		fmt.Fprintln(&b)
		var deleteCount int
		var totalDeleteSize int64
		if m.showLargeFiles && len(m.largeMultiSelected) > 0 {
			deleteCount = len(m.largeMultiSelected)
			for path := range m.largeMultiSelected {
				for _, file := range m.largeFiles {
					if file.Path == path {
						totalDeleteSize += file.Size
						break
					}
				}
			}
		} else if !m.showLargeFiles && len(m.multiSelected) > 0 {
			deleteCount = len(m.multiSelected)
			for path := range m.multiSelected {
				for _, entry := range m.entries {
					if entry.Path == path {
						totalDeleteSize += entry.Size
						break
					}
				}
			}
		}

		if deleteCount > 1 {
			fmt.Fprintf(&b, "%sDelete:%s %d items, %s  %sPress Enter to confirm  |  ESC cancel%s\n",
				colorRed, colorReset,
				deleteCount, humanizeBytes(totalDeleteSize),
				colorGray, colorReset)
		} else {
			fmt.Fprintf(&b, "%sDelete:%s %s, %s  %sPress Enter to confirm  |  ESC cancel%s\n",
				colorRed, colorReset,
				m.deleteTarget.Name, humanizeBytes(m.deleteTarget.Size),
				colorGray, colorReset)
		}
	}
	return b.String()
}

func allOverviewEntriesPending(entries []dirEntry) bool {
	for _, entry := range entries {
		if entry.Size >= 0 {
			return false
		}
	}
	return true
}

func maxLargeFileSize(files []fileEntry) int64 {
	var maxSize int64 = 1
	for _, file := range files {
		if file.Size > maxSize {
			maxSize = file.Size
		}
	}
	return maxSize
}

func maxDirEntrySize(entries []dirEntry) int64 {
	var maxSize int64 = 1
	for _, entry := range entries {
		if entry.Size > maxSize {
			maxSize = entry.Size
		}
	}
	return maxSize
}

func sizeColorForPercent(percent float64) string {
	switch {
	case percent >= 50:
		return colorRed
	case percent >= 20:
		return colorYellow
	case percent >= 5:
		return colorBlue
	default:
		return colorGray
	}
}

func entryHintLabel(entry dirEntry) string {
	if entry.IsDir && isCleanableDir(entry.Path) {
		return fmt.Sprintf("%s🧹%s", colorYellow, colorReset)
	}
	if unusedTime := formatUnusedTime(entry.LastAccess); unusedTime != "" {
		return fmt.Sprintf("%s%s%s", colorGray, unusedTime, colorReset)
	}
	return ""
}

// calculateViewport returns visible rows for the current terminal height.
func calculateViewport(termHeight int, isLargeFiles bool) int {
	if termHeight <= 0 {
		return defaultViewport
	}

	reserved := 6 // Header + footer
	if isLargeFiles {
		reserved = 5
	}

	available := termHeight - reserved

	if available < 1 {
		return 1
	}
	if available > 30 {
		return 30
	}

	return available
}
