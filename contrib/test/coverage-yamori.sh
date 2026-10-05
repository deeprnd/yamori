#!/usr/bin/env bash
# Coverage report generator for yamori (Zig project).
# Usage: coverage-yamori.sh <job-name>
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

JOB="${1:?Usage: coverage-yamori.sh <job-name>}"

_start=$(date +%s)
log() { echo "[$(date +%H:%M:%S)] [$(( $(date +%s) - _start ))s] $*"; }

if [ "$JOB" = "coverage-yamori" ]; then
    command -v kcov >/dev/null 2>&1 || {
        echo "ERROR: kcov not found. Install it with: sudo apt-get install kcov" >&2
        exit 1
    }

    COV_PREFIX="build/yamori-cov"
    COV_RAW="build/yamori-cov/kcov"
    SUMMARY="build/yamori-cov/coverage-summary.json"
    CONFIG="contrib/test/coverage-yamori.json"
    COV_CACHE="build/yamori-cov/.zig-cache"
    COV_GLOBAL_CACHE="build/yamori-cov/.zig-global-cache"

    # ReleaseSafe triggers DWARFv4 output (via LLVM backend), which kcov handles
    # correctly across multiple CUs. Debug mode emits DWARFv5 with per-CU
    # rnglists_base; kcov v44 only honours the first CU's base, silently dropping
    # all subsequent user-code CUs from the coverage report.
    # Coverage builds must not reuse the repository Zig caches.
    rm -rf "$COV_CACHE" "$COV_GLOBAL_CACHE" "$COV_RAW"

    # Build all test executables for coverage (no test execution)
    ZIG_GLOBAL_CACHE_DIR="$COV_GLOBAL_CACHE" zig build \
        --cache-dir "$COV_CACHE" \
        -p "$COV_PREFIX" \
        -Doptimize=ReleaseSafe cov

    # The test binaries live in the zig cache output directory.
    # They are NOT installed to zig-out/bin because cov step skips the install step.
    # Binaries are in hash-named subdirectories, so we use find to locate them.
    COV_CACHE_BINS="$COV_CACHE/o"
    mkdir -p "$COV_RAW"

    # Run tests via kcov for each test binary (find recurses into hash subdirs).
    # Test crashes exit non-zero — we MUST NOT abort here; kcov still collected
    # coverage data from the parts that ran. Collect per-binary exit codes so we
    # can report test failures at the end without losing coverage output.
    set +e
    kcov_exit=0
    find "$COV_CACHE_BINS" -maxdepth 2 -type f -name 'yamori-*-tests' | sort | while read -r bin; do
        name="$(basename "$bin")"
        log "Running kcov on $name"
        kcov --include-pattern=src/*.zig \
            "${COV_RAW}"/"$name" \
            "$bin" || true
    done
    set -e

    # Merge kcov outputs
    MERGED="${COV_RAW}/merged"
    kcov_dirs=()
    for d in "${COV_RAW}"/*/; do
        [ -d "$d" ] || continue
        base="$(basename "$d")"
        [ "$base" = "merged" ] && continue
        kcov_dirs+=("$d")
    done

    if [ "${#kcov_dirs[@]}" -ge 2 ]; then
        kcov --merge "$MERGED" "${kcov_dirs[@]}"
    elif [ "${#kcov_dirs[@]}" -eq 1 ]; then
        mkdir -p "$MERGED"
        ln -sfn "$(realpath "${kcov_dirs[0]}")" "$MERGED"
    else
        echo 'ERROR: no kcov output directories found' >&2
        exit 1
    fi

    python3 contrib/tool/coverage_report.py coverage-yamori \
        "${COV_RAW}/merged" \
        "$SUMMARY" \
        --config "$CONFIG"
else
    echo "Unknown job: $JOB"
    exit 1
fi
