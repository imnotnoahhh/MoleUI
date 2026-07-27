#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "optimize catalog preserves the complete public task contract" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/catalog.sh"

expected=$(cat <<'CONTRACT'
system_maintenance|opt_system_maintenance|DNS & Spotlight Check|DNS & Spotlight Check|Refresh DNS cache & verify Spotlight status|true
cache_refresh|opt_cache_refresh|Finder Cache Refresh|Finder Cache Refresh|Refresh QuickLook thumbnails & icon services cache|true
saved_state_cleanup|opt_saved_state_cleanup|App State Cleanup|App State Cleanup|Remove old saved application states (30+ days)|true
fix_broken_configs|opt_fix_broken_configs|Broken Config Repair|Broken Config Repair|Fix corrupted preferences files|true
network_optimization|opt_network_optimization|Network Cache Refresh|Network Cache Refresh|Optimize DNS cache & restart mDNSResponder|true
sqlite_vacuum|opt_sqlite_vacuum|Database Optimization|Database Optimization|Compress SQLite databases for Mail, Safari & Messages (skips if apps are running)|true
launch_services_rebuild|opt_launch_services_rebuild|LaunchServices Repair|LaunchServices Repair|Repair "Open with" menu & file associations|true
dock_refresh|opt_dock_refresh|Dock Refresh|Dock Refresh|Fix broken icons and visual glitches in the Dock|true
prevent_network_dsstore|opt_prevent_network_dsstore|Prevent Finder .DS_Store|Prevent Finder .DS_Store|Set a persistent Finder preference to stop writing .DS_Store on SMB/AFP/NFS and USB volumes|true
legacy_overrides_audit|opt_legacy_overrides_audit|Legacy Overrides|Legacy Overrides|Remove hidden App Nap and disk-image verification overrides left by old tweak tools|true
memory_pressure_relief|opt_memory_pressure_relief|Memory Optimization|Memory Optimization|Release inactive memory to improve system responsiveness|true
network_stack_optimize|opt_network_stack_optimize|Network Stack Refresh|Network Stack Refresh|Flush routing table and ARP cache to resolve network issues|true
disk_permissions_repair|opt_disk_permissions_repair|Permission Repair|Permission Repair|Fix user directory permission issues|true
spotlight_index_optimize|opt_spotlight_index_optimize|Spotlight Optimization|Spotlight Optimization|Rebuild index if search is slow (smart detection)|true
spotlight_orphan_rules_cleanup|opt_prune_spotlight_orphan_rules|Spotlight Orphan Rules|Spotlight Orphan Rules|Remove Spotlight search-rule entries for apps that are no longer installed|true
periodic_maintenance|opt_periodic_maintenance|Periodic Maintenance|Periodic Maintenance|Run macOS daily/weekly/monthly maintenance scripts if stale|true
shared_file_list_repair|opt_shared_file_list_repair|Shared File Lists|Shared File Lists|Repair corrupted Finder favorites and recent documents|true
disk_verify|opt_disk_verify|Disk Health|Disk Health|Verify filesystem integrity|true
login_items_audit|opt_login_items_audit|Login Items|Login Items Audit|Audit login items for broken entries|true
quarantine_cleanup|opt_quarantine_cleanup|Quarantine Database Cleanup|Quarantine Database Cleanup|Clear Gatekeeper download tracking history|true
launch_agents_cleanup|opt_launch_agents_cleanup|Launch Agents Cleanup|Launch Agents Cleanup|Remove broken LaunchAgents whose binaries no longer exist|true
notification_cleanup|opt_notification_cleanup|Notifications|Notifications|Clean old delivered notifications to reduce database bloat|true
coreduet_cleanup|opt_coreduet_cleanup|Usage Data|Usage Data|Clean old usage tracking data|true
CONTRACT
)

actual=""
for ((index = 0; index < ${#MOLE_OPTIMIZE_ACTIONS[@]}; index++)); do
    printf -v row '%s|%s|%s|%s|%s|%s' \
        "${MOLE_OPTIMIZE_ACTIONS[$index]}" \
        "${MOLE_OPTIMIZE_HANDLERS[$index]}" \
        "${MOLE_OPTIMIZE_HEALTH_NAMES[$index]}" \
        "${MOLE_OPTIMIZE_WHITELIST_NAMES[$index]}" \
        "${MOLE_OPTIMIZE_DESCRIPTIONS[$index]}" \
        "${MOLE_OPTIMIZE_SAFE_VALUES[$index]}"
    actual+="${actual:+$'\n'}$row"
done

[[ "$actual" == "$expected" ]] || { diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"); exit 1; }
optimize_catalog_validate || exit 1
EOF

    [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "health JSON preserves the exact optimization contract" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/check/health_json.sh"

contract_hash=$(
    generate_health_json |
        sed -n '/  "optimizations": \[/,$p' |
        shasum -a 256 |
        awk '{print $1}'
)
expected_hash="9c00db8177c600e35ba56df69c3c3dc078ffefee57d982a96b71b3174cb340ac"
if [[ "$contract_hash" != "$expected_hash" ]]; then
    echo "health optimization contract hash: expected $expected_hash, got $contract_hash"
    exit 1
fi
EOF

    [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimize whitelist preserves every public task label and action" {
    run env HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/manage/whitelist.sh"

contract_hash=$(get_optimize_whitelist_items | shasum -a 256 | awk '{print $1}')
expected_hash="89f0731c4074f1eaeabb4a2c7ab65e14392f28f31ebbc4abefc9f6919406f65a"
if [[ "$contract_hash" != "$expected_hash" ]]; then
    echo "optimize whitelist contract hash: expected $expected_hash, got $contract_hash"
    exit 1
fi
EOF

    [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimize catalog rejects duplicate identities and unsafe tasks" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

if /bin/bash --noprofile --norc < <(
    awk '!changed && /opt_cache_refresh/ {sub(/opt_cache_refresh/, "opt_system_maintenance"); changed=1} {print}' \
        "$PROJECT_ROOT/lib/optimize/catalog.sh"
); then
    echo "duplicate handler passed validation"
    exit 1
fi

if /bin/bash --noprofile --norc < <(
    awk '!changed && / true$/ {sub(/ true$/, " false"); changed=1} {print}' \
        "$PROJECT_ROOT/lib/optimize/catalog.sh"
); then
    echo "unsafe task passed validation"
    exit 1
fi
EOF

    [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
    [[ "$output" == *"Duplicate optimize task handler: opt_system_maintenance"* ]] || return 1
    [[ "$output" == *"Optimize task is not safe for automatic execution: system_maintenance"* ]] || return 1
}

@test "optimize catalog resolves handlers by exact action id" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/optimize/catalog.sh"

if ! handler=$(optimize_catalog_handler_for spotlight_orphan_rules_cleanup); then
    echo "known action did not resolve"
    exit 1
fi
[[ "$handler" == "opt_prune_spotlight_orphan_rules" ]] || exit 1
if optimize_catalog_handler_for unknown_action; then
    echo "unknown action resolved"
    exit 1
fi
EOF

    [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimization task module implements every catalog handler" {
    run env HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"

[[ ${#MOLE_OPTIMIZE_ACTIONS[@]} -eq 23 ]] || exit 1
for handler in "${MOLE_OPTIMIZE_HANDLERS[@]}"; do
    if ! declare -F "$handler" >/dev/null; then
        echo "missing handler: $handler"
        exit 1
    fi
done
EOF

    [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "optimize catalog consumers can be sourced repeatedly" {
    run env HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
source "$PROJECT_ROOT/lib/check/health_json.sh"
source "$PROJECT_ROOT/lib/check/health_json.sh"

declare -F execute_optimization >/dev/null || exit 1
declare -F generate_health_json >/dev/null || exit 1
EOF

    [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}
