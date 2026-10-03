#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf '\n[%s] %s\n' "$1" "$2"
}

run_step() {
  local name="$1"
  shift
  log "run" "$name"
  "$@"
}

usage() {
  cat <<'EOF'
Usage: bash contrib/quality/quality.sh <command>

Commands:
  format-check-zig    Check Zig source formatting (zig fmt)
  format-fix-zig      Fix Zig source formatting (zig fmt)
  lint-check-zig      Lint Zig source (compile check)
  lint-check-yaml     Lint YAML files (yamllint)
  lint-check-spell    Lint all source text (cspell)
EOF
}

# ── Zig Format ───────────────────────────────────────────────────────────────

cmd_format_check_zig() {
  run_step "zig fmt check" zig fmt --check src tests
}

cmd_format_fix_zig() {
  run_step "zig fmt" zig fmt src tests
}

# ── Zig Lint ─────────────────────────────────────────────────────────────────

cmd_lint_check_zig() {
  local cache_dir
  cache_dir="$(git rev-parse --show-toplevel)/build/.zig-cache"
  run_step "zig build check" env ZIG_LOCAL_CACHE_DIR="$cache_dir" zig build check
}

# ── YAML Lint ────────────────────────────────────────────────────────────────

cmd_lint_check_yaml() {
  run_step "yamllint" find . -name '*.yaml' -o -name '*.yml' \
    | grep -vE '^(./build|./zig-out|\.git)/' \
    | xargs -r yamllint -f parsable
}

# ── Spell Check ──────────────────────────────────────────────────────────────

cmd_lint_check_spell() {
  run_step "cspell" cspell lint --no-progress .
}

# ── Dispatcher ────────────────────────────────────────────────────────────────

case "${1:-}" in
  format-check-zig) cmd_format_check_zig ;;
  format-fix-zig)   cmd_format_fix_zig ;;
  lint-check-zig)   cmd_lint_check_zig ;;
  lint-check-yaml)  cmd_lint_check_yaml ;;
  lint-check-spell) cmd_lint_check_spell ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
