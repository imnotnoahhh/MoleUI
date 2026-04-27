#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    CURRENT_VERSION="$(grep '^VERSION=' "$PROJECT_ROOT/mole" | head -1 | sed 's/VERSION=\"\\(.*\\)\"/\\1/')"
    export CURRENT_VERSION

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-update-manager.XXXXXX")"
    export HOME

    mkdir -p "${HOME}/.cache/mole"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    BREW_OUTDATED_COUNT=0
    BREW_FORMULA_OUTDATED_COUNT=0
    BREW_CASK_OUTDATED_COUNT=0
    APPSTORE_UPDATE_COUNT=0
    MACOS_UPDATE_AVAILABLE=false
    MOLE_UPDATE_AVAILABLE=false

    export MOCK_BIN_DIR="$BATS_TMPDIR/mole-mocks-$$"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
}

read_key() {
    echo "ESC"
    return 0
}

@test "ask_for_updates returns 1 when no updates available" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/update.sh"
BREW_OUTDATED_COUNT=0
APPSTORE_UPDATE_COUNT=0
MACOS_UPDATE_AVAILABLE=false
MOLE_UPDATE_AVAILABLE=false
ask_for_updates
EOF

    [ "$status" -eq 1 ]
}

@test "ask_for_updates shows updates and waits for input" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/update.sh"
BREW_OUTDATED_COUNT=5
BREW_FORMULA_OUTDATED_COUNT=3
BREW_CASK_OUTDATED_COUNT=2
APPSTORE_UPDATE_COUNT=1
MACOS_UPDATE_AVAILABLE=true
MOLE_UPDATE_AVAILABLE=true

read_key() { echo "ESC"; return 0; }

ask_for_updates
EOF

    [ "$status" -eq 1 ]  # ESC cancels
    [[ "$output" == *"Update Mole now?"* ]]
    [[ "$output" == *"Run "* ]]
    [[ "$output" == *"brew upgrade"* ]]
    [[ "$output" == *"Software Update"* ]]
    [[ "$output" == *"App Store"* ]]
    [[ "$output" != *"AVAILABLE UPDATES"* ]]
}

@test "ask_for_updates with only macOS update shows settings hint without brew hint" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/update.sh"
BREW_OUTDATED_COUNT=0
BREW_FORMULA_OUTDATED_COUNT=0
BREW_CASK_OUTDATED_COUNT=0
APPSTORE_UPDATE_COUNT=0
MACOS_UPDATE_AVAILABLE=true
MOLE_UPDATE_AVAILABLE=false
ask_for_updates
EOF

    [ "$status" -eq 1 ]
    [[ "$output" == *"Software Update"* ]]
    [[ "$output" != *"brew upgrade"* ]]
    [[ "$output" != *"AVAILABLE UPDATES"* ]]
}

@test "ask_for_updates accepts Enter when updates exist" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/update.sh"
BREW_OUTDATED_COUNT=2
BREW_FORMULA_OUTDATED_COUNT=2
MOLE_UPDATE_AVAILABLE=true
read_key() { echo "ENTER"; return 0; }
ask_for_updates
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Update Mole now?"* ]]
    [[ "$output" == *"yes"* ]]
}

@test "ask_for_updates auto-detects brew updates when counts are unset" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail

cat > "$MOCK_BIN_DIR/brew" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "outdated" && "$2" == "--formula" && "$3" == "--quiet" ]]; then
    printf "wget\njq\n"
    exit 0
fi
if [[ "$1" == "outdated" && "$2" == "--cask" && "$3" == "--quiet" ]]; then
    printf "iterm2\n"
    exit 0
fi
exit 0
SCRIPT
chmod +x "$MOCK_BIN_DIR/brew"

source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/update.sh"
unset BREW_OUTDATED_COUNT BREW_FORMULA_OUTDATED_COUNT BREW_CASK_OUTDATED_COUNT
APPSTORE_UPDATE_COUNT=0
MACOS_UPDATE_AVAILABLE=false
MOLE_UPDATE_AVAILABLE=false

set +e
ask_for_updates
ask_status=$?
set -e

echo "COUNTS:${BREW_OUTDATED_COUNT}:${BREW_FORMULA_OUTDATED_COUNT}:${BREW_CASK_OUTDATED_COUNT}"
exit "$ask_status"
EOF

    [ "$status" -eq 1 ]
    [[ "$output" == *"brew upgrade"* ]]
    [[ "$output" == *"COUNTS:3:2:1"* ]]
    [[ "$output" != *"AVAILABLE UPDATES"* ]]
}

@test "format_brew_update_label lists formula and cask counts" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/update.sh"
BREW_OUTDATED_COUNT=5
BREW_FORMULA_OUTDATED_COUNT=3
BREW_CASK_OUTDATED_COUNT=2
format_brew_update_label
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"3 formula"* ]]
    [[ "$output" == *"2 cask"* ]]
}

@test "perform_updates handles Homebrew success and Mole update" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/update.sh"

BREW_FORMULA_OUTDATED_COUNT=1
BREW_CASK_OUTDATED_COUNT=0
MOLE_UPDATE_AVAILABLE=true

FAKE_DIR="$HOME/fake-script-dir"
mkdir -p "$FAKE_DIR/lib/manage"
cat > "$FAKE_DIR/mole" <<'SCRIPT'
#!/usr/bin/env bash
echo "Already on latest version"
SCRIPT
chmod +x "$FAKE_DIR/mole"
SCRIPT_DIR="$FAKE_DIR/lib/manage"

brew_has_outdated() { return 0; }
start_inline_spinner() { :; }
stop_inline_spinner() { :; }
reset_brew_cache() { echo "BREW_CACHE_RESET"; }
reset_mole_cache() { echo "MOLE_CACHE_RESET"; }
has_sudo_session() { return 1; }
ensure_sudo_session() { echo "ensure_sudo_session_called"; return 1; }

brew() {
    if [[ "$1" == "upgrade" ]]; then
        echo "Upgrading formula"
        return 0
    fi
    return 0
}

get_appstore_update_labels() { return 0; }
get_macos_update_labels() { return 0; }

perform_updates
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating Mole"* ]]
    [[ "$output" == *"Mole updated"* ]]
    [[ "$output" == *"MOLE_CACHE_RESET"* ]]
    [[ "$output" == *"All updates completed"* ]]
}

@test "update_via_homebrew reports already on latest version" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
MOLE_TEST_BREW_UPDATE_OUTPUT="Updated 0 formulae"
MOLE_TEST_BREW_UPGRADE_OUTPUT="Warning: mole 1.7.9 already installed"
MOLE_TEST_BREW_LIST_OUTPUT="mole 1.7.9"
start_inline_spinner() { :; }
stop_inline_spinner() { :; }
brew() {
  case "$1" in
    update) echo "$MOLE_TEST_BREW_UPDATE_OUTPUT";;
    upgrade) echo "$MOLE_TEST_BREW_UPGRADE_OUTPUT";;
    list) if [[ "$2" == "--versions" ]]; then echo "$MOLE_TEST_BREW_LIST_OUTPUT"; fi ;;
  esac
}
export -f brew start_inline_spinner stop_inline_spinner
source "$PROJECT_ROOT/lib/core/common.sh"
update_via_homebrew "1.7.9"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already on latest version"* ]]
}

@test "update_mole skips download when already latest" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" CURRENT_VERSION="$CURRENT_VERSION" PATH="$HOME/fake-bin:/usr/bin:/bin" TERM="dumb" bash --noprofile --norc << 'EOF'
set -euo pipefail
curl() {
  local out=""
  local url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      http*://*)
        url="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -n "$out" ]]; then
    echo "Installer executed" > "$out"
    return 0
  fi

  if [[ "$url" == *"api.github.com"* ]]; then
    echo "{\"tag_name\":\"$CURRENT_VERSION\"}"
  else
    echo "VERSION=\"$CURRENT_VERSION\""
  fi
}
export -f curl

brew() { exit 1; }
export -f brew

"$PROJECT_ROOT/mole" update
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already on latest version"* ]]
}

@test "process_install_output shows install.sh success message with version" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
GREEN='\033[0;32m'
ICON_SUCCESS='✓'
NC='\033[0m'

process_install_output() {
    local output="$1"
    local fallback_version="$2"

    local filtered_output
    filtered_output=$(printf '%s\n' "$output" | sed '/^$/d')
    if [[ -n "$filtered_output" ]]; then
        printf '%s\n' "$filtered_output"
    fi

    if ! printf '%s\n' "$output" | grep -Eq "Updated to latest version|Already on latest version"; then
        local new_version
        new_version=$(printf '%s\n' "$output" | sed -n 's/.*-> \([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        if [[ -z "$new_version" ]]; then
            new_version=$(printf '%s\n' "$output" | sed -n 's/.*version[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        fi
        if [[ -z "$new_version" ]]; then
            new_version=$(command -v mo > /dev/null 2>&1 && mo --version 2> /dev/null | awk 'NR==1 && NF {print $NF}' || echo "")
        fi
        if [[ -z "$new_version" ]]; then
            new_version="$fallback_version"
        fi
        printf '\n%s\n' "${GREEN}${ICON_SUCCESS}${NC} Updated to latest version, ${new_version:-unknown}"
    fi
}

output="Installing Mole...
◎ Mole installed successfully, version 1.23.1"
process_install_output "$output" "1.23.0"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated to latest version, 1.23.1"* ]]
    [[ "$output" != *"1.23.0"* ]]
}

@test "process_install_output uses fallback version when install.sh has no success message" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
GREEN='\033[0;32m'
ICON_SUCCESS='✓'
NC='\033[0m'

process_install_output() {
    local output="$1"
    local fallback_version="$2"

    local filtered_output
    filtered_output=$(printf '%s\n' "$output" | sed '/^$/d')
    if [[ -n "$filtered_output" ]]; then
        printf '%s\n' "$filtered_output"
    fi

    if ! printf '%s\n' "$output" | grep -Eq "Updated to latest version|Already on latest version"; then
        local new_version
        new_version=$(printf '%s\n' "$output" | sed -n 's/.*-> \([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        if [[ -z "$new_version" ]]; then
            new_version=$(printf '%s\n' "$output" | sed -n 's/.*version[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        fi
        if [[ -z "$new_version" ]]; then
            new_version=$(command -v mo > /dev/null 2>&1 && mo --version 2> /dev/null | awk 'NR==1 && NF {print $NF}' || echo "")
        fi
        if [[ -z "$new_version" ]]; then
            new_version="$fallback_version"
        fi
        printf '\n%s\n' "${GREEN}${ICON_SUCCESS}${NC} Updated to latest version, ${new_version:-unknown}"
    fi
}

output="Installing Mole...
Installation completed"
process_install_output "$output" "1.23.1"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Installation completed"* ]]
    [[ "$output" == *"Updated to latest version, 1.23.1"* ]]
}

@test "process_install_output handles empty output with fallback version" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
GREEN='\033[0;32m'
ICON_SUCCESS='✓'
NC='\033[0m'

process_install_output() {
    local output="$1"
    local fallback_version="$2"

    local filtered_output
    filtered_output=$(printf '%s\n' "$output" | sed '/^$/d')
    if [[ -n "$filtered_output" ]]; then
        printf '%s\n' "$filtered_output"
    fi

    if ! printf '%s\n' "$output" | grep -Eq "Updated to latest version|Already on latest version"; then
        local new_version
        new_version=$(printf '%s\n' "$output" | sed -n 's/.*-> \([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        if [[ -z "$new_version" ]]; then
            new_version=$(printf '%s\n' "$output" | sed -n 's/.*version[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        fi
        if [[ -z "$new_version" ]]; then
            new_version=$(command -v mo > /dev/null 2>&1 && mo --version 2> /dev/null | awk 'NR==1 && NF {print $NF}' || echo "")
        fi
        if [[ -z "$new_version" ]]; then
            new_version="$fallback_version"
        fi
        printf '\n%s\n' "${GREEN}${ICON_SUCCESS}${NC} Updated to latest version, ${new_version:-unknown}"
    fi
}

output=""
process_install_output "$output" "1.23.1"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated to latest version, 1.23.1"* ]]
}

@test "process_install_output does not extract wrong parentheses content" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
GREEN='\033[0;32m'
ICON_SUCCESS='✓'
NC='\033[0m'

process_install_output() {
    local output="$1"
    local fallback_version="$2"

    local filtered_output
    filtered_output=$(printf '%s\n' "$output" | sed '/^$/d')
    if [[ -n "$filtered_output" ]]; then
        printf '%s\n' "$filtered_output"
    fi

    if ! printf '%s\n' "$output" | grep -Eq "Updated to latest version|Already on latest version"; then
        local new_version
        new_version=$(printf '%s\n' "$output" | sed -n 's/.*-> \([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        if [[ -z "$new_version" ]]; then
            new_version=$(printf '%s\n' "$output" | sed -n 's/.*version[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' | head -1)
        fi
        if [[ -z "$new_version" ]]; then
            new_version=$(command -v mo > /dev/null 2>&1 && mo --version 2> /dev/null | awk 'NR==1 && NF {print $NF}' || echo "")
        fi
        if [[ -z "$new_version" ]]; then
            new_version="$fallback_version"
        fi
        printf '\n%s\n' "${GREEN}${ICON_SUCCESS}${NC} Updated to latest version, ${new_version:-unknown}"
    fi
}

output="Downloading (progress: 100%)
Done"
process_install_output "$output" "1.23.1"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading (progress: 100%)"* ]]
    [[ "$output" == *"Updated to latest version, 1.23.1"* ]]
    [[ "$output" != *"progress: 100%"* ]] || [[ "$output" == *"Downloading (progress: 100%)"* ]]
}

@test "update_mole with --force reinstalls even when on latest version" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" CURRENT_VERSION="$CURRENT_VERSION" PATH="$HOME/fake-bin:/usr/bin:/bin" TERM="dumb" bash --noprofile --norc << 'EOF'
set -euo pipefail
curl() {
  local out=""
  local url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      http*://*)
        url="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -n "$out" ]]; then
    cat > "$out" << 'INSTALLER'
#!/usr/bin/env bash
echo "Mole installed successfully, version $CURRENT_VERSION"
INSTALLER
    return 0
  fi

  if [[ "$url" == *"api.github.com"* ]]; then
    echo "{\"tag_name\":\"$CURRENT_VERSION\"}"
  else
    echo "VERSION=\"$CURRENT_VERSION\""
  fi
}
export -f curl

brew() { exit 1; }
export -f brew

"$PROJECT_ROOT/mole" update --force
EOF

    [ "$status" -eq 0 ]
    [[ "$output" != *"Already on latest version"* ]]
    [[ "$output" == *"Downloading"* ]] || [[ "$output" == *"Installing"* ]] || [[ "$output" == *"Updated"* ]]
}

@test "update_mole with --nightly uses installer path and passes MOLE_VERSION=main" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" CURRENT_VERSION="$CURRENT_VERSION" PATH="$HOME/fake-bin:/usr/bin:/bin" TERM="dumb" bash --noprofile --norc << 'EOF'
set -euo pipefail
curl() {
  local out=""
  local url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      http*://*)
        url="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -n "$out" ]]; then
    cat > "$out" << 'INSTALLER'
#!/usr/bin/env bash
echo "INSTALLER_MOLE_VERSION=${MOLE_VERSION:-}"
echo "Mole installed successfully, version ${MOLE_VERSION:-unknown}"
INSTALLER
    return 0
  fi

  echo "UNEXPECTED_CURL_URL:$url" >&2
  return 1
}
export -f curl

brew() { return 1; }
export -f brew

"$PROJECT_ROOT/mole" update --nightly
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading nightly installer"* ]]
    [[ "$output" == *"Installing nightly update"* ]]
    [[ "$output" == *"INSTALLER_MOLE_VERSION=main"* ]]
    [[ "$output" == *"Updated to nightly build (main), main"* ]]
}

@test "update_mole with --nightly is rejected for Homebrew installs" {
    local fake_brew_root="$HOME/fake-homebrew"
    local fake_cellar_bin="$fake_brew_root/Cellar/mole/9.9.9/bin"
    local fake_path_bin="$HOME/fake-brew-bin"
    mkdir -p "$fake_cellar_bin" "$fake_path_bin"
    touch "$fake_cellar_bin/mole"
    ln -sf "$fake_cellar_bin/mole" "$fake_path_bin/mole"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$fake_path_bin:/usr/bin:/bin" TERM="dumb" bash --noprofile --norc << 'EOF'
set -euo pipefail
brew() {
  if [[ "${1:-}" == "list" && "${2:-}" == "--formula" ]]; then
    echo "mole"
    return 0
  fi
  if [[ "${1:-}" == "--prefix" ]]; then
    echo "/opt/homebrew"
    return 0
  fi
  return 0
}
export -f brew

"$PROJECT_ROOT/mole" update --nightly
EOF

    [ "$status" -eq 1 ]
    [[ "$output" == *"Nightly update is only available for script installations"* ]]
    [[ "$output" == *"Homebrew installs follow stable releases."* ]]
    [[ "$output" == *"mo update --nightly"* ]]
}

@test "get_homebrew_latest_version prefers brew outdated verbose target version" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
MOLE_TEST_MODE=1 MOLE_SKIP_MAIN=1 source "$PROJECT_ROOT/mole"

brew() {
  if [[ "${1:-}" == "outdated" ]]; then
    echo "tw93/tap/mole (1.29.0) < 1.31.0"
    return 0
  fi
  if [[ "${1:-}" == "info" ]]; then
    echo "==> tw93/tap/mole: stable 9.9.9 (bottled)"
    return 0
  fi
  return 0
}
export -f brew

get_homebrew_latest_version
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == "1.31.0" ]]
}

@test "get_homebrew_latest_version parses brew info fallback with heading prefix" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
MOLE_TEST_MODE=1 MOLE_SKIP_MAIN=1 source "$PROJECT_ROOT/mole"

brew() {
  if [[ "${1:-}" == "outdated" ]]; then
    return 0
  fi
  if [[ "${1:-}" == "info" ]]; then
    echo "==> tw93/tap/mole: stable 1.31.1 (bottled), HEAD"
    return 0
  fi
  return 0
}
export -f brew

get_homebrew_latest_version
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == "1.31.1" ]]
}
