#!/usr/bin/env bash
# Platform detection — single source of truth.
# Returns lowercase: linux/mac/windows and x86/arm.
# Usage: bash platform.sh os | bash platform.sh arch | bash platform.sh platform | bash platform.sh cores

set -euo pipefail

case "${1:-all}" in
  os)
    case "$(uname -s)" in
      Linux*)  echo "linux" ;;
      Darwin*) echo "mac" ;;
      MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
      *)       echo "unknown" ;;
    esac
    ;;
  arch)
    case "$(uname -m)" in
      x86_64|amd64) echo "x86" ;;
      aarch64|arm64) echo "arm" ;;
      *) echo "unknown" ;;
    esac
    ;;
  platform)
    printf '%s-%s' "$(bash "$(dirname "$0")/platform.sh" os)" "$(bash "$(dirname "$0")/platform.sh" arch)"
    ;;
  cores)
    nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
    ;;
  *)
    echo "Usage: platform.sh {os|arch|platform|cores}" >&2
    exit 1
    ;;
esac
