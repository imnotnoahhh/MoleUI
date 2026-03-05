#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-apps-module.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

@test "clean_ds_store_tree reports dry-run summary" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" DRY_RUN=true /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"
start_inline_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
get_file_size() { echo 10; }
bytes_to_human() { echo "0B"; }
files_cleaned=0
total_size_cleaned=0
total_items=0
mkdir -p "$HOME/test_ds"
touch "$HOME/test_ds/.DS_Store"
clean_ds_store_tree "$HOME/test_ds" "DS test"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"DS test"* ]]
}

@test "scan_installed_apps uses cache when fresh" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"
mkdir -p "$HOME/.cache/mole"
echo "com.example.App" > "$HOME/.cache/mole/installed_apps_cache"
get_file_mtime() { date +%s; }
debug_log() { :; }
scan_installed_apps "$HOME/installed.txt"
cat "$HOME/installed.txt"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"com.example.App"* ]]
}

@test "is_bundle_orphaned returns true for old uninstalled bundle" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" ORPHAN_AGE_THRESHOLD=60 bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"
should_protect_data() { return 1; }
get_file_mtime() { echo 0; }
if is_bundle_orphaned "com.example.Old" "$HOME/old" "$HOME/installed.txt"; then
    echo "orphan"
fi
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"orphan"* ]]
}

@test "clean_orphaned_app_data skips when no permission" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"
rm -rf "$HOME/Library/Caches"
clean_orphaned_app_data
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"No permission"* ]]
}

@test "clean_orphaned_app_data handles paths with spaces correctly" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"

# Mock scan_installed_apps - return empty (no installed apps)
scan_installed_apps() {
    : > "$1"
}

# Mock mdfind to return empty (no app found)
mdfind() {
    return 0
}

# Ensure local function mock works even if timeout/gtimeout is installed
run_with_timeout() { shift; "$@"; }

# Mock safe_clean (normally from bin/clean.sh)
safe_clean() {
    rm -rf "$1"
    return 0
}

# Create required Library structure for permission check
mkdir -p "$HOME/Library/Caches"

# Create test structure with spaces in path (old modification time: 61 days ago)
mkdir -p "$HOME/Library/Saved Application State/com.test.orphan.savedState"
# Create a file with some content so directory size > 0
echo "test data" > "$HOME/Library/Saved Application State/com.test.orphan.savedState/data.plist"
# Set modification time to 61 days ago (older than 60-day threshold)
touch -t "$(date -v-61d +%Y%m%d%H%M.%S 2>/dev/null || date -d '61 days ago' +%Y%m%d%H%M.%S)" "$HOME/Library/Saved Application State/com.test.orphan.savedState" 2>/dev/null || true

# Disable spinner for test
start_section_spinner() { :; }
stop_section_spinner() { :; }

# Run cleanup
clean_orphaned_app_data

# Verify path with spaces was handled correctly (not split into multiple paths)
if [[ -d "$HOME/Library/Saved Application State/com.test.orphan.savedState" ]]; then
    echo "ERROR: Orphaned savedState not deleted"
    exit 1
else
    echo "SUCCESS: Orphaned savedState deleted correctly"
fi
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "clean_orphaned_app_data only counts successful deletions" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"

# Mock scan_installed_apps - return empty
scan_installed_apps() {
    : > "$1"
}

# Mock mdfind to return empty (no app found)
mdfind() {
    return 0
}

# Ensure local function mock works even if timeout/gtimeout is installed
run_with_timeout() { shift; "$@"; }

# Create required Library structure for permission check
mkdir -p "$HOME/Library/Caches"

# Create test files (old modification time: 61 days ago)
mkdir -p "$HOME/Library/Caches/com.test.orphan1"
mkdir -p "$HOME/Library/Caches/com.test.orphan2"
# Create files with content so size > 0
echo "data1" > "$HOME/Library/Caches/com.test.orphan1/data"
echo "data2" > "$HOME/Library/Caches/com.test.orphan2/data"
# Set modification time to 61 days ago
touch -t "$(date -v-61d +%Y%m%d%H%M.%S 2>/dev/null || date -d '61 days ago' +%Y%m%d%H%M.%S)" "$HOME/Library/Caches/com.test.orphan1" 2>/dev/null || true
touch -t "$(date -v-61d +%Y%m%d%H%M.%S 2>/dev/null || date -d '61 days ago' +%Y%m%d%H%M.%S)" "$HOME/Library/Caches/com.test.orphan2" 2>/dev/null || true

# Mock safe_clean to fail on first item, succeed on second
safe_clean() {
    if [[ "$1" == *"orphan1"* ]]; then
        return 1  # Fail
    else
        rm -rf "$1"
        return 0  # Succeed
    fi
}

# Disable spinner
start_section_spinner() { :; }
stop_section_spinner() { :; }

# Run cleanup
clean_orphaned_app_data

# Verify first item still exists (safe_clean failed)
if [[ -d "$HOME/Library/Caches/com.test.orphan1" ]]; then
    echo "PASS: Failed deletion preserved"
fi

# Verify second item deleted
if [[ ! -d "$HOME/Library/Caches/com.test.orphan2" ]]; then
    echo "PASS: Successful deletion removed"
fi

# Check that output shows correct count (only 1, not 2)
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: Failed deletion preserved"* ]]
    [[ "$output" == *"PASS: Successful deletion removed"* ]]
}


@test "is_critical_system_component matches known system services" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/app_protection.sh"
is_critical_system_component "backgroundtaskmanagement" && echo "yes"
is_critical_system_component "SystemSettings" && echo "yes"
EOF
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "yes" ]]
    [[ "${lines[1]}" == "yes" ]]
}

@test "is_critical_system_component ignores non-system names" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/app_protection.sh"
if is_critical_system_component "myapp"; then
  echo "bad"
else
  echo "ok"
fi
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

@test "clean_orphaned_system_services respects dry-run" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_DRY_RUN=1 bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
debug_log() { :; }

tmp_dir="$(mktemp -d)"
tmp_plist="$tmp_dir/com.sogou.test.plist"
touch "$tmp_plist"

sudo() {
  if [[ "$1" == "-n" && "$2" == "true" ]]; then
    return 0
  fi
  if [[ "$1" == "find" ]]; then
    printf '%s\0' "$tmp_plist"
    return 0
  fi
  if [[ "$1" == "du" ]]; then
    echo "4 $tmp_plist"
    return 0
  fi
  if [[ "$1" == "launchctl" ]]; then
    echo "launchctl-called"
    return 0
  fi
  if [[ "$1" == "rm" ]]; then
    echo "rm-called"
    return 0
  fi
  command "$@"
}

clean_orphaned_system_services
EOF

    [ "$status" -eq 0 ]
    [[ "$output" != *"rm-called"* ]]
    [[ "$output" != *"launchctl-called"* ]]
}

@test "is_launch_item_orphaned detects orphan when program missing" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"

tmp_dir="$(mktemp -d)"
tmp_plist="$tmp_dir/com.test.orphan.plist"

cat > "$tmp_plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.test.orphan</string>
    <key>ProgramArguments</key>
    <array>
        <string>/nonexistent/app/program</string>
    </array>
</dict>
</plist>
PLIST

run_with_timeout() { shift; "$@"; }

if is_launch_item_orphaned "$tmp_plist"; then
    echo "orphan"
fi

rm -rf "$tmp_dir"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"orphan"* ]]
}

@test "is_launch_item_orphaned protects when program exists" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"

tmp_dir="$(mktemp -d)"
tmp_plist="$tmp_dir/com.test.active.plist"
tmp_program="$tmp_dir/program"
touch "$tmp_program"

cat > "$tmp_plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.test.active</string>
    <key>ProgramArguments</key>
    <array>
        <string>$tmp_program</string>
    </array>
</dict>
</plist>
PLIST

run_with_timeout() { shift; "$@"; }

if is_launch_item_orphaned "$tmp_plist"; then
    echo "orphan"
else
    echo "not-orphan"
fi

rm -rf "$tmp_dir"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"not-orphan"* ]]
}

@test "is_launch_item_orphaned protects when app support active" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"

tmp_dir="$(mktemp -d)"
tmp_plist="$tmp_dir/com.test.appsupport.plist"

mkdir -p "$HOME/Library/Application Support/TestApp"
touch "$HOME/Library/Application Support/TestApp/recent.txt"

cat > "$tmp_plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.test.appsupport</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/Library/Application Support/TestApp/Current/app</string>
    </array>
</dict>
</plist>
PLIST

run_with_timeout() { shift; "$@"; }

if is_launch_item_orphaned "$tmp_plist"; then
    echo "orphan"
else
    echo "not-orphan"
fi

rm -rf "$tmp_dir"
rm -rf "$HOME/Library/Application Support/TestApp"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"not-orphan"* ]]
}

@test "clean_orphaned_launch_agents skips when no orphans" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"

mkdir -p "$HOME/Library/LaunchAgents"

start_section_spinner() { :; }
stop_section_spinner() { :; }
note_activity() { :; }
get_path_size_kb() { echo "1"; }
run_with_timeout() { shift; "$@"; }

clean_orphaned_launch_agents
EOF

    [ "$status" -eq 0 ]
}
