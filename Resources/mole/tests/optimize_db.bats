#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT

	ORIGINAL_HOME="${HOME:-}"
	export ORIGINAL_HOME

	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-optimize-db.XXXXXX")"
	export HOME
}

teardown_file() {
	if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
		rm -rf "$HOME"
	fi
	if [[ -n "${ORIGINAL_HOME:-}" ]]; then
		export HOME="$ORIGINAL_HOME"
	fi
}

create_logical_file() {
	local path="$1"
	local size="$2"

	if command -v mkfile > /dev/null 2>&1; then
		mkfile -n "$size" "$path"
	else
		truncate -s "$size" "$path"
	fi
}

@test "opt_notification_cleanup reports healthy when db is small" {
	local tmp_dir nc_db_dir
	tmp_dir=$(mktemp -d)
	nc_db_dir="$tmp_dir/com.apple.notificationcenter/db2"
	mkdir -p "$nc_db_dir"
	create_logical_file "$nc_db_dir/db" 1k

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<EOF
set -euo pipefail
source "\$PROJECT_ROOT/lib/core/common.sh"
source "\$PROJECT_ROOT/lib/optimize/tasks.sh"
getconf() { echo "$tmp_dir"; }
opt_notification_cleanup
EOF

	rm -rf "$tmp_dir"
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
}

@test "opt_notification_cleanup warns when sqlite3 fails" {
	local tmp_dir nc_db_dir
	tmp_dir=$(mktemp -d)
	nc_db_dir="$tmp_dir/com.apple.notificationcenter/db2"
	mkdir -p "$nc_db_dir"
	create_logical_file "$nc_db_dir/db" 60m

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<EOF
set -euo pipefail
source "\$PROJECT_ROOT/lib/core/common.sh"
source "\$PROJECT_ROOT/lib/optimize/tasks.sh"
getconf() { echo "$tmp_dir"; }
sqlite3() { return 1; }
opt_notification_cleanup
EOF

	rm -rf "$tmp_dir"
	[ "$status" -eq 0 ]
	[[ "$output" == *"busy or locked"* ]]
}

@test "opt_coreduet_cleanup reports healthy when db is small" {
	local tmp_dir
	tmp_dir=$(mktemp -d)
	mkdir -p "$tmp_dir/Library/Application Support/Knowledge"
	local knowledge_db="$tmp_dir/Library/Application Support/Knowledge/knowledgeC.db"
	create_logical_file "$knowledge_db" 1k

	run env HOME="$tmp_dir" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<EOF
set -euo pipefail
source "\$PROJECT_ROOT/lib/core/common.sh"
source "\$PROJECT_ROOT/lib/optimize/tasks.sh"
opt_coreduet_cleanup
EOF

	rm -rf "$tmp_dir"
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
}

@test "opt_coreduet_cleanup warns when sqlite3 fails" {
	local tmp_dir fake_bin
	tmp_dir=$(mktemp -d)
	fake_bin="$tmp_dir/bin"
	mkdir -p "$tmp_dir/Library/Application Support/Knowledge" "$fake_bin"
	local knowledge_db="$tmp_dir/Library/Application Support/Knowledge/knowledgeC.db"
	create_logical_file "$knowledge_db" 1k

	cat > "$fake_bin/du" <<'EOF'
#!/bin/bash
echo "112640 total"
EOF
	chmod +x "$fake_bin/du"

	run env HOME="$tmp_dir" PROJECT_ROOT="$PROJECT_ROOT" PATH="$fake_bin:$PATH" bash --noprofile --norc <<EOF
set -euo pipefail
source "\$PROJECT_ROOT/lib/core/common.sh"
source "\$PROJECT_ROOT/lib/optimize/tasks.sh"
sqlite3() { return 1; }
opt_coreduet_cleanup
EOF

	rm -rf "$tmp_dir"
	[ "$status" -eq 0 ]
	[[ "$output" == *"busy or locked"* ]]
}
