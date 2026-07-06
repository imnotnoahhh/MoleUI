#!/usr/bin/env bats
# Verify NO_COLOR support per https://no-color.org.

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT
}

@test "NO_COLOR strips ANSI escapes from base color vars" {
	run env NO_COLOR=1 PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"
printf '%s' "<${GREEN}><${RED}><${YELLOW}><${BLUE}><${CYAN}><${PURPLE}><${PURPLE_BOLD}><${GRAY}><${NC}>"
EOF
	[ "$status" -eq 0 ]
	[ "$output" = "<><><><><><><><><>" ]
}

@test "default keeps ANSI escapes in base color vars" {
	run env -u NO_COLOR PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"
printf '%s' "${GREEN}x${NC}"
EOF
	[ "$status" -eq 0 ]
	[ "$output" = $'\033[0;32mx\033[0m' ]
}

@test "empty NO_COLOR keeps ANSI escapes per spec" {
	run env NO_COLOR="" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"
printf '%s' "${RED}y${NC}"
EOF
	[ "$status" -eq 0 ]
	[ "$output" = $'\033[0;31my\033[0m' ]
}
