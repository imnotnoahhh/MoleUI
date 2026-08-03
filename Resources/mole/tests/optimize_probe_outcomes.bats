#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT

	TEST_HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-optimize-probes.XXXXXX")"
	export TEST_HOME
}

teardown_file() {
	if [[ "$TEST_HOME" == "${BATS_TEST_DIRNAME}/tmp-optimize-probes."* ]]; then
		rm -rf "$TEST_HOME"
	fi
}

@test "system maintenance reports a failed Spotlight probe" {
	run env HOME="$TEST_HOME/system" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
unset MOLE_TEST_NO_AUTH MOLE_TEST_MODE
flush_dns_cache() { return 0; }
mkdir -p "$HOME/bin"
printf '#!/bin/bash\nexit 7\n' > "$HOME/bin/mdutil"
chmod +x "$HOME/bin/mdutil"
PATH="$HOME/bin:$PATH"

execute_optimization system_maintenance
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to verify Spotlight index"* ]] || return 1
}

@test "Spotlight optimization reports a failed status probe" {
	run env HOME="$TEST_HOME/spotlight" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
run_with_timeout() { return 124; }

execute_optimization spotlight_index_optimize
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to inspect Spotlight index (exit=124)"* ]] || return 1
}

@test "quarantine cleanup reports a failed row-count probe" {
	run env HOME="$TEST_HOME/quarantine" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
db="$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
mkdir -p "$(dirname "$db")"
touch "$db"
sqlite3() { return 0; }
should_protect_path() { return 1; }
run_with_timeout() { return 7; }

execute_optimization quarantine_cleanup
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to inspect quarantine database"* ]] || return 1
}

@test "login item audit reports a failed snapshot" {
	run env HOME="$TEST_HOME/login" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
unset MOLE_TEST_NO_AUTH MOLE_TEST_MODE
_login_items_snapshot() { return 7; }

execute_optimization login_items_audit
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to inspect login items"* ]] || return 1
}

@test "notification cleanup reports a failed size probe" {
	run env HOME="$TEST_HOME/notification" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
getconf() { echo "$HOME/runtime"; }
db="$HOME/runtime/com.apple.notificationcenter/db2/db"
mkdir -p "$(dirname "$db")"
touch "$db"
opt_existing_file_size_kb_strict() { return 124; }

execute_optimization notification_cleanup
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to inspect Notification Center database size"* ]] || return 1
}

@test "CoreDuet cleanup reports a failed size probe" {
	run env HOME="$TEST_HOME/coreduet-size" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
db="$HOME/Library/Application Support/Knowledge/knowledgeC.db"
mkdir -p "$(dirname "$db")"
touch "$db"
run_with_timeout() { return 124; }

execute_optimization coreduet_cleanup
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to inspect Knowledge database size"* ]] || return 1
}

@test "sudo-dependent maintenance is skipped when admin access is denied" {
	run env HOME="$TEST_HOME/admin" PROJECT_ROOT="$PROJECT_ROOT" MOLE_OPTIMIZE_SUDO_AVAILABLE=false /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
mdutil() { echo "UNEXPECTED_MDUTIL"; return 0; }

execute_optimization system_maintenance
execute_optimization network_optimization
[[ "$(optimize_outcome_count skipped)" == "2" ]] || exit 1
[[ "$(optimize_outcome_count failed)" == "0" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"admin access required"* ]] || return 1
	[[ "$output" != *"UNEXPECTED_MDUTIL"* ]] || return 1
}

@test "Spotlight optimization reports failed speed probes" {
	run env HOME="$TEST_HOME/spotlight-speed" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
run_with_timeout() {
    if [[ "$2" == "mdutil" ]]; then
        echo "Indexing enabled."
        return 0
    fi
    return 7
}
is_ac_power() { return 0; }
time_file="$HOME/probe-time"
echo 0 > "$time_file"
get_epoch_seconds() {
    local call
    call=$(cat "$time_file")
    call=$((call + 1))
    echo "$call" > "$time_file"
    if ((call % 2 == 1)); then
        echo 100
    else
        echo 110
    fi
}
sleep() { return 0; }

execute_optimization spotlight_index_optimize
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Spotlight speed check failed (2 probe(s))"* ]] || return 1
}

@test "saved state cleanup reports a failed discovery scan" {
	run env HOME="$TEST_HOME/saved-scan" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
mkdir -p "$HOME/Library/Saved Application State" "$HOME/bin"
printf '#!/bin/bash\nexit 7\n' > "$HOME/bin/find"
chmod +x "$HOME/bin/find"
PATH="$HOME/bin:$PATH"

execute_optimization saved_state_cleanup
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to scan old saved states"* ]] || return 1
	[[ "$output" != *"App saved states optimized"* ]] || return 1
	[[ "$output" != *"Failed to remove"* ]] || return 1
}

@test "shared file list repair reports a failed discovery scan" {
	run env HOME="$TEST_HOME/shared-scan" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
mkdir -p "$HOME/Library/Application Support/com.apple.sharedfilelist" "$HOME/bin"
printf '#!/bin/bash\nexit 7\n' > "$HOME/bin/find"
chmod +x "$HOME/bin/find"
PATH="$HOME/bin:$PATH"

execute_optimization shared_file_list_repair
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to scan shared file lists"* ]] || return 1
	[[ "$output" != *"Failed to repair"* ]] || return 1
}

@test "optimize external probes use bounded execution" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
tasks_file="$PROJECT_ROOT/lib/optimize/tasks.sh"

system_body=$(sed -n '/^opt_system_maintenance() {/,/^}/p' "$tasks_file")
saved_body=$(sed -n '/^opt_saved_state_cleanup() {/,/^}/p' "$tasks_file")
network_body=$(sed -n '/^opt_network_stack_optimize() {/,/^}/p' "$tasks_file")
vpn_body=$(sed -n '/^has_active_vpn_interface() {/,/^}/p' "$tasks_file")
shared_body=$(sed -n '/^opt_shared_file_list_repair() {/,/^}/p' "$tasks_file")

[[ "$system_body" == *'run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" mdutil -s /'* ]] || exit 1
[[ "$saved_body" == *'run_with_timeout "$MOLE_TIMEOUT_MEDIUM_PROBE_SEC" find'* ]] || exit 1
[[ "$network_body" == *'run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" route -n get default'* ]] || exit 1
[[ "$network_body" == *'run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" dscacheutil -q host'* ]] || exit 1
[[ "$vpn_body" == *'run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" scutil --nc list'* ]] || exit 1
[[ "$vpn_body" == *'run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" route -n get default'* ]] || exit 1
[[ "$shared_body" == *'run_with_timeout "$MOLE_TIMEOUT_MEDIUM_PROBE_SEC" find'* ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}

@test "network probe timeout never authorizes maintenance" {
	run env HOME="$TEST_HOME/network-timeout" PROJECT_ROOT="$PROJECT_ROOT" MOLE_ASSUME_VPN_ACTIVE=0 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"

run_with_timeout() { return 124; }
sudo() { echo "UNEXPECTED_SUDO"; return 0; }

execute_optimization network_stack_optimize
[[ "$(optimize_outcome_count failed)" == "1" ]] || exit 1
[[ "$(optimize_outcome_count applied)" == "0" ]] || exit 1
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Network health check timed out"* ]] || return 1
	[[ "$output" != *"Network routing table refreshed"* ]] || return 1
	[[ "$output" != *"UNEXPECTED_SUDO"* ]] || return 1
}

@test "network probes preserve the caller errexit mode" {
	run env HOME="$TEST_HOME/vpn-errexit" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"

run_with_timeout() { return 124; }
sudo() { echo "UNEXPECTED_SUDO"; return 0; }
set +e
execute_optimization network_stack_optimize
false
echo "survived:$(optimize_outcome_count failed)"
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"Failed to inspect active VPN state"* ]] || return 1
	[[ "$output" == *"survived:1"* ]] || return 1
	[[ "$output" != *"Network routing table refreshed"* ]] || return 1
	[[ "$output" != *"UNEXPECTED_SUDO"* ]] || return 1
}

@test "optimize tasks never toggle the caller errexit option" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
tasks_file="$PROJECT_ROOT/lib/optimize/tasks.sh"
if grep -nE '^[[:space:]]*set [+-]e([[:space:]]|$)' "$tasks_file"; then
    exit 1
fi
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}
