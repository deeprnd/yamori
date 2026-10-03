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
Usage: bash contrib/security/security.sh <command>

Commands:
  gitleaks-check-yamori   Secret scanning on Yamori source tree

  sanitize-check-yamori   Build + test with Zig ReleaseSafe (safety checks)

  # Convenience
  sanitize-check-all      Runs all sanitizer checks (currently just yamori)

Notes:
  - CodeQL, seccomp, proof, and ASan/UBSan checks are N/A — Yamori is a
    pure-Zig project with no C substrate, no Qt terminal, and no CBMC proof.
  - gitleaks and Zig ReleaseSafe are the only active security checks.
EOF
}

# ── Gitleaks: Yamori ────────────────────────────────────────────────────────

cmd_gitleaks_check_yamori() {
  run_step "gitleaks yamori" \
    gitleaks detect --no-git --verbose --source "$ROOT_DIR/src" \
      --config contrib/security/gitleaks-yamori.toml
  # Also scan tests/ and any other source dirs
  gitleaks detect --no-git --verbose --source "$ROOT_DIR/tests" \
    --config contrib/security/gitleaks-yamori.toml
}

# ── Sanitize: Zig ReleaseSafe ──────────────────────────────────────────────

cmd_sanitize_check_yamori() {
  if ! command -v zig >/dev/null 2>&1; then
    echo "sanitize-check-yamori requires zig on PATH" >&2
    return 1
  fi

  run_step "zig build test ReleaseSafe" \
    zig build test -Doptimize=ReleaseSafe
}

# ── Qt / CodeQL / Seccomp / Proof (all N/A) ────────────────────────────────

cmd_codeql_check_yamori() {
  echo "N/A — CodeQL does not support Zig"
}

cmd_seccomp_check_yamori() {
  echo "N/A — Yamori has no C substrate tile infrastructure"
}

cmd_proof_check_yamori() {
  echo "N/A — no CBMC formal verification for Zig"
}

cmd_sanitize_check_qt() {
  echo "N/A — no Qt terminal in Yamori"
}

# ── All ─────────────────────────────────────────────────────────────────────

cmd_sanitize_check_all() {
  cmd_sanitize_check_yamori
}

# ── Dispatch ────────────────────────────────────────────────────────────────

case "${1:-}" in
  gitleaks-check-yamori)  cmd_gitleaks_check_yamori ;;
  sanitize-check-yamori)  cmd_sanitize_check_yamori ;;
  sanitize-check-all)     cmd_sanitize_check_all ;;
  codeql-check-yamori)    cmd_codeql_check_yamori ;;
  seccomp-check-yamori)   cmd_seccomp_check_yamori ;;
  proof-check-yamori)     cmd_proof_check_yamori ;;
  sanitize-check-qt)      cmd_sanitize_check_qt ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
