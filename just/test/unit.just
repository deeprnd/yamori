# ── Zig local cache ───────────────────────────────────────────────────────────
ZIG_CACHE := "$(git rev-parse --show-toplevel)/build/.zig-cache"
ZIG_GLOBAL_CACHE := "$(git rev-parse --show-toplevel)/build/.zig-global-cache"

# ── Zig prefix ────────────────────────────────────────────────────────────────
ZIG_PREFIX := "$(git rev-parse --show-toplevel)/build/zig-out"

# ── Platform Detection ────────────────────────────────────────────────────────
os := `bash contrib/platform.sh os`
arch := `bash contrib/platform.sh arch`
cpu_count := `bash contrib/platform.sh cores`

# ── Zig test options ──────────────────────────────────────────────────────────
ZIG_TEST_OPTS := "-Doptimize=Debug"

# ── Zig build helper ──────────────────────────────────────────────────────────
# Run zig build with cache dirs in build/ for clean repo root.
zig-test step:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build {{ step }} {{ ZIG_TEST_OPTS }})

# ── Subsystem test recipes ────────────────────────────────────────────────────
test-formula-linux-x86:
	zig-test test-formula

test-formula-linux-arm:
	zig-test test-formula

test-registry-linux-x86:
	zig-test test-registry

test-registry-linux-arm:
	zig-test test-registry

test-cycle-linux-x86:
	zig-test test-cycle

test-cycle-linux-arm:
	zig-test test-cycle

test-dep-resolve-linux-x86:
	zig-test test-dep-resolve

test-dep-resolve-linux-arm:
	zig-test test-dep-resolve

test-arrow-linux-x86:
	zig-test test-arrow

test-arrow-linux-arm:
	zig-test test-arrow

test-result-linux-x86:
	zig-test test-result

test-result-linux-arm:
	zig-test test-result

test-provenance-linux-x86:
	zig-test test-provenance

test-provenance-linux-arm:
	zig-test test-provenance

# ── Bare dispatchers ──────────────────────────────────────────────────────────

# Run all unit tests across every subsystem.
test-unit-all:
	zig-test test

# Per-subsystem dispatchers — route to correct platform recipe.
test-formula:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-formula-linux-x86 ;;
		linux-arm) just test-formula-linux-arm ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-registry:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-registry-linux-x86 ;;
		linux-arm) just test-registry-linux-arm ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-cycle:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-cycle-linux-x86 ;;
		linux-arm) just test-cycle-linux-arm ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-dep-resolve:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-dep-resolve-linux-x86 ;;
		linux-arm) just test-dep-resolve-linux-arm ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-arrow:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-arrow-linux-x86 ;;
		linux-arm) just test-arrow-linux-arm ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-result:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-result-linux-x86 ;;
		linux-arm) just test-result-linux-arm ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-provenance:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-provenance-linux-x86 ;;
		linux-arm) just test-provenance-linux-arm ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

# ── Alias convention ──────────────────────────────────────────────────────────
# Platform aliases forward to the canonical linux-x86 recipe.
# These use make's target-dependency syntax (NOT just's `alias = recipe`).
# Only linux-x86 and linux-arm are supported; other platforms fail explicitly.

test-formula-linux-arm: test-formula-linux-x86
test-registry-linux-arm: test-registry-linux-x86
test-cycle-linux-arm: test-cycle-linux-x86
test-dep-resolve-linux-arm: test-dep-resolve-linux-x86
test-arrow-linux-arm: test-arrow-linux-x86
test-result-linux-arm: test-result-linux-x86
test-provenance-linux-arm: test-provenance-linux-x86
