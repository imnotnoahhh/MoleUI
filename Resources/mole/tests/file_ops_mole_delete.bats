#!/usr/bin/env bats

# Tests for mole_delete in lib/core/file_ops.sh.
# Exercises permanent mode (default), trash mode (via MOLE_TEST_TRASH_DIR
# so Finder is never invoked), dry-run, and the deletions log.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    SANDBOX="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-mole-delete.XXXXXX")"
    export SANDBOX
    export MOLE_DELETE_LOG="$SANDBOX/deletions.log"
    export MOLE_TEST_TRASH_DIR="$SANDBOX/Trash"
    export MOLE_TEST_NO_AUTH=1
    unset MOLE_DELETE_MODE
    unset MOLE_DRY_RUN
}

teardown() {
    rm -rf "$SANDBOX"
}

prelude() {
    cat <<EOF
set -euo pipefail
export MOLE_DELETE_LOG="$MOLE_DELETE_LOG"
export MOLE_TEST_TRASH_DIR="$MOLE_TEST_TRASH_DIR"
export MOLE_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
EOF
}

@test "mole_delete defaults to permanent mode and removes the target" {
    local victim="$SANDBOX/victim"
    mkdir -p "$victim"
    : > "$victim/keep.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    # Trash dir must remain empty in permanent mode.
    [[ -z "$(ls -A "$MOLE_TEST_TRASH_DIR" 2> /dev/null || true)" ]]
}

@test "mole_delete trash mode moves the target instead of rm -rf" {
    local victim="$SANDBOX/victim_trash"
    mkdir -p "$victim"
    printf 'payload' > "$victim/data.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=trash
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    # Something landed in the stub trash dir.
    [[ -n "$(ls -A "$MOLE_TEST_TRASH_DIR" 2> /dev/null || true)" ]]
}

@test "mole_delete moves sudo-required paths to invoking user Trash" {
    local victim="$SANDBOX/victim_sudo_trash"
    local fake_bin="$SANDBOX/bin"
    local fake_home="$SANDBOX/home"
    local trace="$SANDBOX/trace.log"

    mkdir -p "$fake_bin" "$fake_home"
    mkdir -p "$victim"
    printf 'payload' > "$victim/data.txt"

    cat > "$fake_bin/trash" <<'SH'
#!/bin/bash
printf 'trash %s\n' "$*" >> "$MOLE_TEST_TRACE"
exit 99
SH
    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
"$@"
SH
    cat > "$fake_bin/osascript" <<'SH'
#!/bin/bash
printf 'osascript %s\n' "$*" >> "$MOLE_TEST_TRACE"
exit 98
SH
    chmod +x "$fake_bin/trash" "$fake_bin/sudo" "$fake_bin/osascript"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export PATH="$fake_bin:\$PATH"
export HOME="$fake_home"
export MOLE_TEST_TRACE="$trace"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_create_privileged_trash_stage() {
    local stage="$SANDBOX/stage-sudo-trash"
    mkdir -p "\$stage"
    printf '%s\n' "\$stage"
}
mole_delete "$victim" true
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    [[ -d "$fake_home/.Trash/$(basename "$victim")" ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/mv ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c '^sudo -n trash ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^trash ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^osascript ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    # The per-item stage lives inside a root-owned 0711 parent, so an
    # unprivileged rmdir cannot unlink it and would leak one directory per move.
    [[ "$(grep -c "^sudo -n /bin/rmdir $SANDBOX/stage-sudo-trash\$" "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    # The shared staging root stays: removing it raced with concurrent runs.
    [[ "$(grep -c 'rmdir /Library/MoleTrashStaging' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ ! -d "$SANDBOX/stage-sudo-trash" ]] || return 1
    # -x stops the recursive chown at a mount point nested inside the payload;
    # the same-device gate only covers the payload root.
    [[ "$(grep -c '^sudo -n /usr/sbin/chown -Rhx ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "ok" ]
}

@test "mole_delete refuses symlinked invoking user Trash for sudo-required paths" {
    local victim="$SANDBOX/victim_sudo_symlink_trash"
    local fake_bin="$SANDBOX/bin"
    local fake_home="$SANDBOX/home"
    local redirected="$SANDBOX/redirected"
    local trace="$SANDBOX/trace.log"

    mkdir -p "$fake_bin" "$fake_home" "$redirected" "$victim"
    printf 'payload' > "$victim/data.txt"
    ln -s "$redirected" "$fake_home/.Trash"

    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
"$@"
SH
    chmod +x "$fake_bin/sudo"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export PATH="$fake_bin:\$PATH"
export HOME="$fake_home"
export MOLE_TEST_TRACE="$trace"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
mole_delete "$victim" true
EOF

    [ "$status" -ne 0 ]
    [[ -e "$victim" ]] || return 1
    [[ -z "$(ls -A "$redirected" 2> /dev/null || true)" ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/mv ' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "trash-failed" ]
}

@test "mole_delete uses unique Trash name for sudo-required path conflicts" {
    local victim="$SANDBOX/conflict_app"
    local fake_bin="$SANDBOX/bin"
    local fake_home="$SANDBOX/home"
    local trace="$SANDBOX/trace.log"

    mkdir -p "$fake_bin" "$fake_home/.Trash" "$victim"
    printf 'payload' > "$victim/data.txt"
    mkdir -p "$fake_home/.Trash/$(basename "$victim")"

    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
"$@"
SH
    chmod +x "$fake_bin/sudo"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export PATH="$fake_bin:\$PATH"
export HOME="$fake_home"
export MOLE_TEST_TRACE="$trace"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_create_privileged_trash_stage() {
    local stage="$SANDBOX/stage-conflict-trash"
    mkdir -p "\$stage"
    printf '%s\n' "\$stage"
}
mole_delete "$victim" true
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    [[ -d "$fake_home/.Trash/$(basename "$victim")" ]] || return 1
    [[ -n "$(find "$fake_home/.Trash" -mindepth 1 -maxdepth 1 -name "$(basename "$victim").*" -print -quit)" ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/mv ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "ok" ]
}

@test "sudo Trash preserves staged payload without privileged rollback after handoff" {
    local victim="$SANDBOX/recovery_app"
    local fake_home="$SANDBOX/home"
    local stage="$SANDBOX/recovery-stage"
    local trace="$SANDBOX/recovery-sudo.log"

    mkdir -p "$fake_home" "$victim"
    printf 'payload' > "$victim/data.txt"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export MOLE_DELETE_MODE=trash
export HOME="$fake_home"
_mole_privileged_path_has_mutable_ancestor() { return 1; }
_mole_create_privileged_trash_stage() {
    command chmod 500 "$fake_home/.Trash"
    mkdir -p "$stage"
    printf '%s\n' "$stage"
}
sudo() {
    [[ "\${1:-}" == "-n" ]] && shift
    printf '%s\n' "\$*" >> "$trace"
    "\$@"
}
set +e
mole_delete "$victim" true
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"RC=1"* ]] || return 1
    [[ "$output" == *"item preserved for recovery"* ]] || return 1
    [[ ! -e "$victim" ]] || return 1
    [[ -f "$stage/item/data.txt" ]] || return 1
    [[ "$(grep -c "/bin/rm -rf $stage" "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c "/bin/mv $stage/item $victim" "$trace" 2> /dev/null || true)" -eq 0 ]]
}

@test "privileged Trash staging never uses world-writable Library Caches" {
    run grep -nF '/Library/Caches/.mole-trash' "$PROJECT_ROOT/lib/core/file_ops.sh"
    [ "$status" -ne 0 ]

    run grep -nF 'stage_root="/Library/MoleTrashStaging"' "$PROJECT_ROOT/lib/core/file_ops.sh"
    [ "$status" -eq 0 ]
}

@test "Microsoft Word app path uses the direct Trash mover without trash or Finder" {
    local fake_home="$SANDBOX/home"
    local trace="$SANDBOX/direct-route.log"
    mkdir -p "$fake_home"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
_mole_move_path_to_user_trash() {
    printf 'direct:%s:%s\n' "\$1" "\$2" >> "$trace"
    return 0
}
trash() {
    printf 'trash:%s\n' "\$*" >> "$trace"
    return 99
}
osascript() {
    printf 'osascript:%s\n' "\$*" >> "$trace"
    return 98
}
_mole_path_requires_direct_trash "/Applications/Microsoft Word.app"
! _mole_path_requires_direct_trash "/Applications/Utilities/Microsoft Word.app"
! _mole_path_requires_direct_trash "/Applications/Microsoft Word.app/Contents"
_mole_move_to_trash "/Applications/Microsoft Word.app" false
EOF

    [ "$status" -eq 0 ]
    grep -qF "direct:/Applications/Microsoft Word.app:false" "$trace"
    [[ "$(grep -c '^trash:' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^osascript:' "$trace" 2> /dev/null || true)" -eq 0 ]]
}

@test "normal app data uses direct Trash with a unique name and mode 0700" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Containers/com.microsoft.Word"
    local existing="$fake_home/.Trash/com.microsoft.Word"
    local trace="$SANDBOX/direct-user.log"
    mkdir -p "$victim" "$existing"
    printf 'document state' > "$victim/state.db"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
trash() {
    printf 'trash:%s\n' "\$*" >> "$trace"
    return 99
}
osascript() {
    printf 'osascript:%s\n' "\$*" >> "$trace"
    return 98
}
mole_delete "$victim" false
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    [[ -d "$existing" ]] || return 1
    [[ -n "$(find "$fake_home/.Trash" -mindepth 1 -maxdepth 1 -name 'com.microsoft.Word.*' -print -quit)" ]] || return 1
    [ "$(stat -f '%Lp' "$fake_home/.Trash")" = "700" ]
    [[ "$(grep -c '^trash:' "$trace" 2> /dev/null || true)" -eq 0 ]] || return 1
    [[ "$(grep -c '^osascript:' "$trace" 2> /dev/null || true)" -eq 0 ]]
}

@test "normal direct Trash refuses a symlinked invoking user Trash" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Application Scripts/com.microsoft.Word"
    local redirected="$SANDBOX/redirected"
    mkdir -p "$victim" "$redirected"
    ln -s "$redirected" "$fake_home/.Trash"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
mole_delete "$victim" false
EOF

    [ "$status" -ne 0 ]
    [[ -d "$victim" ]] || return 1
    [[ -z "$(ls -A "$redirected" 2> /dev/null || true)" ]]
}

@test "direct Trash reports TCC denial and never falls back to permanent delete" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Containers/com.microsoft.Word"
    local trace="$SANDBOX/privacy-denied.log"
    mkdir -p "$victim"
    printf 'document state' > "$victim/state.db"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
mv() {
    printf 'mv: %s: Operation not permitted\n' "\$2" >&2
    return 1
}
trash() {
    printf 'trash\n' >> "$trace"
    return 99
}
osascript() {
    printf 'osascript\n' >> "$trace"
    return 98
}
safe_remove() {
    printf 'safe_remove\n' >> "$trace"
    return 97
}
set +e
mole_delete "$victim" false
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_PRIVACY_DENIED ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -d "$victim" ]] || return 1
    [[ "$output" == *"App Data or Full Disk Access"* ]] || return 1
    [[ "$output" != *"Touch ID"* ]] || return 1
    [[ "$output" == *"RC=14"* ]] || return 1
    [[ ! -s "$trace" ]] || return 1
    [ "$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")" = "privacy-denied" ]
}

@test "direct Trash recognizes lowercase permission denied" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Group Containers/UBF8T346G9.Office"
    mkdir -p "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
mv() {
    printf 'mv: permission denied\n' >&2
    return 1
}
set +e
_mole_move_path_to_user_trash "$victim" false
rc=\$?
set -e
printf 'RC=%s\n' "\$rc"
[[ \$rc -eq \$MOLE_ERR_PRIVACY_DENIED ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -d "$victim" ]] || return 1
    [[ "$output" == *"RC=14"* ]]
}

@test "direct Trash generic failure stays closed" {
    local fake_home="$SANDBOX/home"
    local victim="$fake_home/Library/Application Scripts/com.microsoft.Word"
    local trace="$SANDBOX/generic-failure.log"
    mkdir -p "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
unset MOLE_TEST_TRASH_DIR
unset MOLE_TEST_NO_AUTH
export HOME="$fake_home"
export MOLE_DELETE_MODE=trash
export MOLE_UNINSTALL_MODE=1
mv() {
    printf 'mv: input/output error\n' >&2
    return 1
}
trash() {
    printf 'trash\n' >> "$trace"
    return 99
}
osascript() {
    printf 'osascript\n' >> "$trace"
    return 98
}
safe_remove() {
    printf 'safe_remove\n' >> "$trace"
    return 97
}
set +e
mole_delete "$victim" false
rc=\$?
set -e
[[ \$rc -eq 1 ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -d "$victim" ]] || return 1
    [[ ! -s "$trace" ]] || return 1
    [[ "$output" == *"refusing permanent delete"* ]]
}

@test "privacy denial diagnosis recommends terminal privacy access, not Touch ID" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
diagnose_removal_failure "\$MOLE_ERR_PRIVACY_DENIED" "Microsoft Word"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"macOS privacy permission denied"* ]] || return 1
    [[ "$output" == *"App Data or Full Disk Access"* ]] || return 1
    [[ "$output" != *"touchid"* ]] || return 1
    [[ "$output" != *"Touch ID"* ]]
}

@test "mole_delete writes a tab-separated log line per call" {
    local victim="$SANDBOX/logged"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ -s "$MOLE_DELETE_LOG" ]] || return 1

    # Expect 5 tab-separated fields: timestamp, mode, size_kb, status, path.
    local fields
    fields=$(awk -F'\t' 'END { print NF }' "$MOLE_DELETE_LOG")
    [ "$fields" -eq 5 ]

    # Status column must be "ok" for a successful permanent delete.
    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "ok" ]
}

@test "mole_delete rejects symlinks to protected system paths" {
    local victim="$SANDBOX/system-link"
    ln -s "/System" "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$victim"
EOF

    [ "$status" -eq 1 ]
    [[ -L "$victim" ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "rejected" ]
}

@test "mole_delete dry-run does not touch the filesystem but still logs" {
    local victim="$SANDBOX/dry"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DRY_RUN=1
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ -e "$victim" ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "dry-run" ]
}

@test "mole_delete records a forensic log entry for rejected paths" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "/tmp/../etc/hosts"
EOF

    [ "$status" -ne 0 ]
    # Rejection IS logged (security-relevant), with status="rejected" and size=0.
    # Audit trails need to distinguish refused-by-policy from never-attempted.
    [[ -s "$MOLE_DELETE_LOG" ]] || return 1
    local status_col size_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    size_col=$(awk -F'\t' 'END { print $3 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "rejected" ]
    [ "$size_col" = "0" ]
}

@test "mole_delete is a no-op on a non-existent path" {
    run /bin/bash --noprofile --norc <<EOF
$(prelude)
mole_delete "$SANDBOX/does-not-exist"
EOF

    [ "$status" -eq 0 ]
    [[ ! -s "$MOLE_DELETE_LOG" ]]
}

@test "mole_delete rejects unknown delete mode without touching target" {
    local victim="$SANDBOX/invalid_mode_target"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=surprise
mole_delete "$victim"
EOF

    [ "$status" -ne 0 ]
    [[ -e "$victim" ]] || return 1

    local mode_col status_col
    mode_col=$(awk -F'\t' 'END { print $2 }' "$MOLE_DELETE_LOG")
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$mode_col" = "surprise" ]
    [ "$status_col" = "invalid-mode" ]
    [[ "$output" == *'expected "permanent" or "trash"'* ]]
}

@test "mole_delete warns once for repeated invalid delete mode" {
    local first="$SANDBOX/invalid_mode_first"
    local second="$SANDBOX/invalid_mode_second"
    : > "$first"
    : > "$second"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=surprise
set +e
mole_delete "$first"
first_rc=\$?
mole_delete "$second"
second_rc=\$?
set -e
[[ \$first_rc -ne 0 && \$second_rc -ne 0 ]] || exit 1
EOF

    [ "$status" -eq 0 ]
    [[ -e "$first" ]] || return 1
    [[ -e "$second" ]] || return 1
    [[ "$(grep -c 'invalid MOLE_DELETE_MODE' <<< "$output")" -eq 1 ]]
}

@test "mole_delete trash failure leaves target in place" {
    local victim="$SANDBOX/fallback_target"
    : > "$victim"

    # Pointing MOLE_TEST_TRASH_DIR at a non-writable parent forces the stub
    # trash move to fail, exercising the fallback path.
    local blocked="$SANDBOX/blocked/Trash"
    mkdir -p "$(dirname "$blocked")"
    chmod 0555 "$(dirname "$blocked")"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=trash
export MOLE_TEST_TRASH_DIR="$blocked"
mole_delete "$victim"
EOF

    chmod 0755 "$(dirname "$blocked")"

    [ "$status" -ne 0 ]
    [[ -e "$victim" ]] || return 1

    local status_col
    status_col=$(awk -F'\t' 'END { print $4 }' "$MOLE_DELETE_LOG")
    [ "$status_col" = "trash-failed" ]
    [[ "$output" == *"refusing permanent delete"* ]]
}

@test "mole_delete warns once for repeated Trash failures" {
    local first="$SANDBOX/trash_fail_first"
    local second="$SANDBOX/trash_fail_second"
    : > "$first"
    : > "$second"

    local blocked="$SANDBOX/blocked/Trash"
    mkdir -p "$(dirname "$blocked")"
    chmod 0555 "$(dirname "$blocked")"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_DELETE_MODE=trash
export MOLE_TEST_TRASH_DIR="$blocked"
set +e
mole_delete "$first"
first_rc=\$?
mole_delete "$second"
second_rc=\$?
set -e
[[ \$first_rc -ne 0 && \$second_rc -ne 0 ]] || exit 1
EOF

    chmod 0755 "$(dirname "$blocked")"

    [ "$status" -eq 0 ]
    [[ -e "$first" ]] || return 1
    [[ -e "$second" ]] || return 1
    [[ "$(grep -c "Trash unavailable" <<< "$output")" -eq 1 ]]
}

@test "mole_delete records 'unknown' (not 0) when size measurement fails" {
    # Override get_path_size_kb to simulate a measurement failure (non-numeric
    # output, non-zero exit). The actual delete still goes through safe_remove
    # so the file is removed; only the log size column should differ.
    local victim="$SANDBOX/measureless"
    : > "$victim"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
get_path_size_kb() { echo "ERR"; return 1; }
mole_delete "$victim"
EOF

    [ "$status" -eq 0 ]
    [[ ! -e "$victim" ]] || return 1
    local size_col
    size_col=$(awk -F'\t' 'END { print $3 }' "$MOLE_DELETE_LOG")
    [ "$size_col" = "unknown" ]
}

@test "mole_delete warns once per session when audit log is unwritable" {
    local victim="$SANDBOX/log_blocked"
    : > "$victim"
    local broken_log_dir="$SANDBOX/no_write/logs"
    mkdir -p "$(dirname "$broken_log_dir")"
    chmod 0555 "$(dirname "$broken_log_dir")"

    run /bin/bash --noprofile --norc <<EOF
set -euo pipefail
export MOLE_DELETE_LOG="$broken_log_dir/deletions.log"
export MOLE_TEST_TRASH_DIR="$MOLE_TEST_TRASH_DIR"
export MOLE_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
mole_delete "$victim"
# Second call in the same shell must NOT print again.
: > "$SANDBOX/second_victim"
mole_delete "$SANDBOX/second_victim"
EOF

    chmod 0755 "$(dirname "$broken_log_dir")"

    [ "$status" -eq 0 ]
    # Warning visible exactly once.
    local warn_count
    warn_count=$(printf '%s\n' "$output" | grep -c "deletions audit log unavailable" || true)
    [ "$warn_count" = "1" ]
}

@test "get_path_size_kb bounds a hung du instead of wedging the sizing worker" {
    # Regression: the primary sizing du (file_ops.sh get_path_size_kb) ran
    # WITHOUT run_with_timeout while every sibling call site was bounded, so
    # one stalled SMB/FUSE mount wedged a parallel scan worker forever. The
    # stub du sleeps far past the 1s override; a bounded helper returns "0"
    # quickly, an unbounded one trips the bats timeout.
    local stub_dir="$SANDBOX/stub-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/du" <<'STUB'
#!/bin/bash
sleep 30
echo "999999 /"
STUB
    chmod +x "$stub_dir/du"

    local victim_dir="$SANDBOX/big-dir"
    mkdir -p "$victim_dir"

    local started elapsed
    started=$SECONDS
    run /bin/bash --noprofile --norc <<EOF
set -euo pipefail
export PATH="$stub_dir:\$PATH"
export MOLE_TIMEOUT_DISK_VERIFY_SEC=1
export MOLE_TEST_NO_AUTH=1
source "$PROJECT_ROOT/lib/core/common.sh"
get_path_size_kb "$victim_dir"
EOF
    elapsed=$((SECONDS - started))

    [ "$status" -eq 0 ]
    [ "$output" = "0" ] || return 1
    # Generous ceiling: 1s timeout + escalation grace, never 30s.
    [ "$elapsed" -lt 10 ] || return 1
}

# The stage-root preparation is the part with a concurrency contract, and the
# Trash tests above mock the whole stage creator, so it needs its own coverage:
# two Mole processes can both observe a missing root, and a plain mkdir would
# make the loser abort a Trash move that was perfectly safe.
@test "privileged Trash stage root tolerates a concurrent creator" {
    local stage_root="$SANDBOX/stage-root"
    local trace="$SANDBOX/root-prep.log"
    local fake_bin="$SANDBOX/bin"

    mkdir -p "$fake_bin"
    # `mkdir` without -p loses the race: another process created the root between
    # this process's check and its own mkdir, which is the EEXIST the fix
    # absorbs. chown/chmod cannot really run unprivileged, so they report
    # success; reaching them at all is the evidence that mkdir did not abort.
    cat > "$fake_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$MOLE_TEST_TRACE"
if [[ "${1:-}" == "-n" ]]; then
    shift
fi
case "$1" in
    */mkdir)
        shift
        if [[ "${1:-}" == "-p" ]]; then
            shift
            mkdir -p "$@"
            exit $?
        fi
        mkdir "$@" 2> /dev/null
        exit $?
        ;;
    */chown | */chmod) exit 0 ;;
esac
"$@"
SH
    chmod +x "$fake_bin/sudo"
    # The concurrent winner already created it.
    mkdir -p "$stage_root"
    : > "$trace"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export PATH="$fake_bin:\$PATH"
export MOLE_TEST_TRACE="$trace"
_mole_prepare_privileged_trash_stage_root "$stage_root"
EOF

    # mkdir -p absorbed the existing root and the flow continued into the
    # ownership steps. A plain mkdir returns EEXIST and never reaches them.
    [[ "$(grep -c '^sudo -n /bin/mkdir -p ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c '^sudo -n /usr/sbin/chown 0:0 ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    [[ "$(grep -c '^sudo -n /bin/chmod 711 ' "$trace" 2> /dev/null || true)" -eq 1 ]] || return 1
    # The sandbox root is owned by the test user, so the verification gate must
    # still refuse it: tolerating EEXIST must not weaken the ownership check.
    [ "$status" -ne 0 ] || return 1
    [[ -d "$stage_root" ]]
}

@test "privileged Trash stage root refuses a symlinked root" {
    local real_dir="$SANDBOX/elsewhere"
    local stage_root="$SANDBOX/stage-root-link"
    local trace="$SANDBOX/root-link.log"

    mkdir -p "$real_dir"
    ln -s "$real_dir" "$stage_root"
    : > "$trace"

    run /bin/bash --noprofile --norc <<EOF
$(prelude)
export MOLE_TEST_TRACE="$trace"
sudo() { printf 'sudo %s\n' "\$*" >> "$trace"; return 0; }
_mole_prepare_privileged_trash_stage_root "$stage_root"
EOF

    [ "$status" -ne 0 ] || return 1
    # Nothing privileged may run against a symlinked root.
    [[ ! -s "$trace" ]]
}
