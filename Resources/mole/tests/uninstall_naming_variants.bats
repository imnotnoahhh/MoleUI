#!/usr/bin/env bats
# Test naming variant detection for find_app_files (Issue #377)

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-naming.XXXXXX")"
    export HOME

    source "$PROJECT_ROOT/lib/core/base.sh"
    source "$PROJECT_ROOT/lib/core/log.sh"
    source "$PROJECT_ROOT/lib/core/app_protection.sh"
}

teardown_file() {
    if [[ -d "$HOME" && "$HOME" =~ tmp-naming ]]; then
        rm -rf "$HOME"
    fi
    export HOME="$ORIGINAL_HOME"
}

setup() {
    find "$HOME" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    source "$PROJECT_ROOT/lib/core/base.sh"
    source "$PROJECT_ROOT/lib/core/log.sh"
    source "$PROJECT_ROOT/lib/core/app_protection.sh"
}

@test "find_app_files detects lowercase-hyphen variant (maestro-studio)" {
    mkdir -p "$HOME/.config/maestro-studio"
    echo "test" > "$HOME/.config/maestro-studio/config.json"

    result=$(find_app_files "com.maestro.studio" "Maestro Studio")

    [[ "$result" =~ .config/maestro-studio ]]
}

@test "find_app_files detects no-space variant (MaestroStudio)" {
    mkdir -p "$HOME/Library/Application Support/MaestroStudio"
    echo "test" > "$HOME/Library/Application Support/MaestroStudio/data.db"

    result=$(find_app_files "com.maestro.studio" "Maestro Studio")

    [[ "$result" =~ "Library/Application Support/MaestroStudio" ]]
}

@test "find_app_files detects Maestro Studio auth directory (.mobiledev)" {
    mkdir -p "$HOME/.mobiledev"
    echo "token" > "$HOME/.mobiledev/authtoken"

    result=$(find_app_files "com.maestro.studio" "Maestro Studio")

    [[ "$result" =~ .mobiledev ]]
}

@test "find_app_files extracts base name from version suffix (Zed Nightly -> zed)" {
    mkdir -p "$HOME/.config/zed"
    mkdir -p "$HOME/Library/Application Support/Zed"
    echo "test" > "$HOME/.config/zed/settings.json"
    echo "test" > "$HOME/Library/Application Support/Zed/cache.db"

    result=$(find_app_files "dev.zed.Zed-Nightly" "Zed Nightly")

    [[ "$result" =~ .config/zed ]]
    [[ "$result" =~ "Library/Application Support/Zed" ]]
}

@test "find_app_files detects Zed channel variants in HTTPStorages only" {
    mkdir -p "$HOME/Library/HTTPStorages/dev.zed.Zed-Preview"
    mkdir -p "$HOME/Library/Application Support/Firefox/Profiles/default/storage/default/https+++zed.dev"
    echo "test" > "$HOME/Library/HTTPStorages/dev.zed.Zed-Preview/data"
    echo "test" > "$HOME/Library/Application Support/Firefox/Profiles/default/storage/default/https+++zed.dev/data"

    result=$(find_app_files "dev.zed.Zed-Nightly" "Zed Nightly")

    [[ "$result" =~ Library/HTTPStorages/dev\.zed\.Zed-Preview ]]
    [[ ! "$result" =~ storage/default/https\+\+\+zed\.dev ]]
}

@test "find_app_files detects multiple naming variants simultaneously" {
    mkdir -p "$HOME/.config/maestro-studio"
    mkdir -p "$HOME/Library/Application Support/MaestroStudio"
    mkdir -p "$HOME/Library/Application Support/Maestro-Studio"
    mkdir -p "$HOME/.local/share/maestrostudio"

    echo "test" > "$HOME/.config/maestro-studio/config.json"
    echo "test" > "$HOME/Library/Application Support/MaestroStudio/data.db"
    echo "test" > "$HOME/Library/Application Support/Maestro-Studio/prefs.json"
    echo "test" > "$HOME/.local/share/maestrostudio/cache.db"

    result=$(find_app_files "com.maestro.studio" "Maestro Studio")

    [[ "$result" =~ .config/maestro-studio ]]
    [[ "$result" =~ "Library/Application Support/MaestroStudio" ]]
    [[ "$result" =~ "Library/Application Support/Maestro-Studio" ]]
    [[ "$result" =~ .local/share/maestrostudio ]]
}

@test "find_app_files handles multi-word version suffix (Firefox Developer Edition)" {
    mkdir -p "$HOME/.local/share/firefox"
    echo "test" > "$HOME/.local/share/firefox/profiles.ini"

    result=$(find_app_files "org.mozilla.firefoxdeveloperedition" "Firefox Developer Edition")

    [[ "$result" =~ .local/share/firefox ]]
}

@test "find_app_files does not match empty app name" {
    mkdir -p "$HOME/Library/Application Support/test"

    result=$(find_app_files "com.test" "" 2>/dev/null || true)

    [[ ! "$result" =~ "Library/Application Support"$ ]]
}
