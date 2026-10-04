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
zig build test step:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build {{ step }} {{ ZIG_TEST_OPTS }})

# ── Subsystem test recipes ────────────────────────────────────────────────────
# Only linux-x86 recipes here; linux-arm aliases forward below.
test-formula-linux-x86:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test-formula {{ ZIG_TEST_OPTS }})

test-registry-linux-x86:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test-registry {{ ZIG_TEST_OPTS }})

test-cycle-linux-x86:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test-cycle {{ ZIG_TEST_OPTS }})

test-dep-resolve-linux-x86:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test-dep-resolve {{ ZIG_TEST_OPTS }})

test-arrow-linux-x86:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test-arrow {{ ZIG_TEST_OPTS }})

test-result-linux-x86:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test-result {{ ZIG_TEST_OPTS }})

test-provenance-linux-x86:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test-provenance {{ ZIG_TEST_OPTS }})

# ── Bare dispatchers ──────────────────────────────────────────────────────────

# Run all unit tests across every subsystem.
test-unit-all:
	(cd {{ justfile_dir }} && \
		ZIG_LOCAL_CACHE_DIR="{{ ZIG_CACHE }}" \
		ZIG_GLOBAL_CACHE_DIR="{{ ZIG_GLOBAL_CACHE }}" \
		zig build test {{ ZIG_TEST_OPTS }})

# Per-subsystem dispatchers — route to correct platform recipe.
test-formula:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-formula-linux-x86 ;;
		linux-arm) just test-formula-linux-x86 ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-registry:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-registry-linux-x86 ;;
		linux-arm) just test-registry-linux-x86 ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-cycle:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-cycle-linux-x86 ;;
		linux-arm) just test-cycle-linux-x86 ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-dep-resolve:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-dep-resolve-linux-x86 ;;
		linux-arm) just test-dep-resolve-linux-x86 ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-arrow:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-arrow-linux-x86 ;;
		linux-arm) just test-arrow-linux-x86 ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-result:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-result-linux-x86 ;;
		linux-arm) just test-result-linux-x86 ;;
		*) echo "unsupported platform: {{ os }}-{{ arch }}" >&2; exit 1 ;;
	esac

test-provenance:
	#!/usr/bin/env bash
	set -euo pipefail
	case "{{ os }}-{{ arch }}" in
		linux-x86) just test-provenance-linux-x86 ;;
		linux-arm) just test-provenance-linux-x86 ;;
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
