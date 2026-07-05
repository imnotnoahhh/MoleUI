#!/bin/bash
# Format the just-edited file with the project's configured formatters.
# Invoked by .claude/settings.json as a PostToolUse hook on Edit/MultiEdit/Write.
# Stdin is the Claude Code hook payload (JSON). Failures must not block the edit.

set -u

# Extract file path from hook payload. Tolerate missing jq.
if ! command -v jq > /dev/null 2>&1; then
    exit 0
fi

FILE=$(jq -r '.tool_input.file_path // empty' 2> /dev/null || true)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0

case "$FILE" in
    *.sh | */mole)
        if command -v shfmt > /dev/null 2>&1; then
            shfmt -i 4 -ci -sr -w "$FILE" > /dev/null 2>&1 || true
        fi
        ;;
    *.go)
        if command -v goimports > /dev/null 2>&1; then
            goimports -w -local github.com/tw93/Mole "$FILE" > /dev/null 2>&1 || true
        elif command -v gofmt > /dev/null 2>&1; then
            gofmt -w "$FILE" > /dev/null 2>&1 || true
        fi
        ;;
esac

exit 0
