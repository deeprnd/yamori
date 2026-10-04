# Testing

This document describes the Yamori testing workflow and all available `just` commands for running unit tests and coverage.

## Prerequisites

- **Zig** — built via `just install` or installed from the Zig release page
- **kcov** — for coverage collection (`sudo apt-get install kcov` on Ubuntu/Debian)

## Unit Tests

All unit tests are organized into subsystems and can be run individually or as a complete suite.

### Run All Unit Tests

```bash
just test-unit-all
```

This builds and runs all 61 tests across every subsystem (dependency resolution, cycle detection, arrow adapter, runValuation, and provenance).

### Run Subsystem Tests

Each subsystem has a dedicated test command:

| Subsystem | Command |
| --- | --- |
| Dependency Resolution | `just test-dep-resolve` |
| Cycle Detection | `just test-cycle` |
| Arrow Adapter | `just test-arrow` |
| Result Frame / runValuation | `just test-result` |
| Formula Registry | `just test-registry` |
| Provenance | `just test-provenance` |

### Platform-Agnostic Dispatch

Each command (`test-dep-resolve`, `test-cycle`, etc.) automatically routes to the correct platform-specific recipe. On `linux-x86`, it runs the native binary; on `linux-arm`, it forwards to the x86 recipe (cross-platform support via `contrib/platform.sh`).

### Build System

Tests are built via direct `zig build` invocations:

```bash
ZIG_LOCAL_CACHE_DIR="build/.zig-cache" \
ZIG_GLOBAL_CACHE_DIR="build/.zig-global-cache" \
zig build test-formula -Doptimize=Debug
```

Cache directories are placed in `build/` to keep the repo root clean. The `-Doptimize=Debug` flag enables debug symbols and assertions.

## Coverage

Coverage is collected using **kcov**, which instruments the test binary and produces an HTML report.

### Run Coverage

```bash
just test-cov-yamori
```

This executes all tests under kcov and writes an HTML report to `build/yamori-cov/`.

### Coverage Configuration

- kcov is invoked via `just/test/coverage.just`
- The coverage script is at `just/test/contrib/test/coverage-yamori.sh`
- Output directory: `build/yamori-cov/`

## Test Architecture

### Subsystems

1. **Dependency Resolution** (`test-dep-resolve`) — topological ordering via Kahn's algorithm, lexicographic tiebreaking, determinism verification
2. **Cycle Detection** (`test-cycle`) — DFS-based cycle detection with three-color marking, self-references, undefined references
3. **Arrow Adapter** (`test-arrow`) — operation execution (add, subtract, multiply, divide), error handling, C ABI validation
4. **Result Frame / runValuation** (`test-result`) — graph traversal, source data handling, fail-closed behavior, diamond execution
5. **Provenance** (`test-provenance`) — provenance chain construction, query by name, all_provenance_built

### Memory Safety

All tests are verified to pass with **zero memory leaks**. The memory ownership model:

- `ResultFrame` owns ArrowArray pointers, data slices, and buffers_holder arrays
- `StringHashMap` keys are freed via explicit iteration before `deinit()`
- `Provenance` values are deinitialized before map destruction
- `resultFrameFree()` handles all cleanup; callers must `alloc.destroy(frame)` after

## Verification

After any code change, verify:

```bash
just test-unit-all       # All tests pass
just test-cov-yamori     # Coverage completes without errors
```

## Related Docs

- [Observability](./observability.md) — runtime signals and diagnostics
- [Security](./security.md) — security checks and sanitization
- [Telemetry](./telemetry.md) — telemetry configuration
