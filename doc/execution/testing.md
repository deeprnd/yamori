# Yamori Testing

This document describes the Yamori testing workflow, test layers, and all available `just` commands for running unit tests and coverage.

## Prerequisites

- **Zig** — built via `just install` or installed from the Zig release page
- **kcov** — for coverage collection (`sudo apt-get install kcov` on Ubuntu/Debian)

## Test-Driven Development

Yamori development should follow test-driven development. After planning a change and before implementing it, write the narrowest test that captures the new behavior, regression, or invariant. The implementation is complete only when that test passes and the broader validation still passes.

Do not rely on custom throwaway verification scripts as the only proof for new behavior. If a one-off script or ad hoc command is needed to prove a feature, that is a signal that a unit test is missing. Add the test to the correct subsystem and wire it through `build.zig` as appropriate.

## Test Layers

Yamori's test suite consists of a single layer: **Zig harness unit tests**. There are no integration, e2e, or system tests at this stage because Yamori is a library-focused codebase without external runtime dependencies (no model servers, no live topology, no Qt GUI).

All tests live in `src/main.zig` as Zig `test` blocks, and `build.zig` defines separate test executables for each subsystem. The test graph is:

| Test executable | Subsystem | `just` command |
|---|---|---|
| `yamori-tests` | All subsystems | `just test-unit-all` |
| `yamori-formula-tests` | Formula definitions, operations | `just test-formula` |
| `yamori-registry-tests` | Named formula registry | `just test-registry` |
| `yamori-cycle-tests` | Cycle detection (DFS) | `just test-cycle` |
| `yamori-dep-resolve-tests` | Dependency resolution (Kahn's) | `just test-dep-resolve` |
| `yamori-arrow-tests` | Arrow adapter, operation execution | `just test-arrow` |
| `yamori-result-tests` | Result frame, graph traversal | `just test-result` |
| `yamori-provenance-tests` | Provenance chain construction | `just test-provenance` |

## Test Commands

All commands are invoked from the repository root.

### Run All Unit Tests

```bash
just test-unit-all
```

This builds and runs all test executables across every subsystem.

### Run Subsystem Tests

Each subsystem has a dedicated test command:

| Subsystem | Command |
|---|---|
| Formula definitions | `just test-formula` |
| Result frame / runValuation | `just test-result` |
| Formula registry | `just test-registry` |
| Cycle detection | `just test-cycle` |
| Dependency resolution | `just test-dep-resolve` |
| Arrow adapter | `just test-arrow` |
| Provenance | `just test-provenance` |

### Platform-Agnostic Dispatch

Each command (`test-formula`, `test-cycle`, etc.) automatically routes to the correct platform-specific recipe. On `linux-x86`, it runs the native binary; on `linux-arm`, it forwards to the x86 recipe (cross-platform support via `contrib/platform.sh`).

### Build System

Tests are built via `zig build` invocations defined in `build.zig`. Cache directories are placed in `build/` to keep the repo root clean. The `-Doptimize=Debug` flag enables debug symbols and assertions.

```bash
ZIG_LOCAL_CACHE_DIR="build/.zig-cache" \
ZIG_GLOBAL_CACHE_DIR="build/.zig-global-cache" \
zig build test-formula -Doptimize=Debug
```

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
5. **Formula Definitions** (`test-formula`) — formula construction, named formula registry, dependency graph building
6. **Formula Registry** (`test-registry`) — formula lookup by name, registration, schema validation
7. **Provenance** (`test-provenance`) — provenance chain construction, query by name, `all_provenance_built`

### Test Organization

All test code lives in `src/main.zig` as Zig `test` blocks. Each test block is tagged with a subsystem identifier (e.g., `test "dep-resolve/basic-topo"`) so the test runner can filter by pattern. The `build.zig` file creates separate `addTest` executables per subsystem, each importing all modules (`yamori`, `capability`, `registry`, `gsl_adapter`, `arrow_adapter`) so that tests can exercise the full stack for their subsystem.

### Memory Safety

All tests are verified to pass with **zero memory leaks**. The memory ownership model:

- `ResultFrame` owns ArrowArray pointers, data slices, and buffers_holder arrays
- `StringHashMap` keys are freed via explicit iteration before `deinit()`
- `Provenance` values are deinitialized before map destruction
- `resultFrameFree()` handles all cleanup; callers must `alloc.destroy(frame)` after

## Test Selection Rules

Run the narrowest relevant set first, then broaden when risk is high. The test task source of truth is the repository root `justfile`; run these commands from the repository root unless noted otherwise.

- **Formula definition change** (operators, expressions, formula types): `just test-formula`
- **Registry change** (lookup, registration, schema): `just test-registry`
- **Dependency graph change** (topological sort, cycle detection): `just test-dep-resolve` and `just test-cycle`
- **Arrow adapter change** (operation execution, C ABI): `just test-arrow`
- **Result frame change** (graph traversal, valuation logic): `just test-result`
- **Provenance change** (chain construction, query): `just test-provenance`
- **Cross-subsystem change** (affects multiple modules or shared types): `just test-unit-all`
- **Coverage-sensitive change**: `just test-cov-yamori`
- **Full validation**: `just test-unit-all` followed by `just test-cov-yamori`

## Harness Details

### Zig Test Blocks

Yamori uses Zig's built-in `test` blocks for all unit tests. Each block runs independently and can be filtered by name via `zig test --filter <pattern>`. The `build.zig` file wires each subsystem into its own test executable so that coverage reporting is scoped per-subsystem.

### Test Imports

Each test executable imports all modules to ensure full-stack coverage within its subsystem:

```zig
test_exe_root.addImport("yamori", lib);
test_exe_root.addImport("capability", cap_mod);
test_exe_root.addImport("registry", reg_mod);
test_exe_root.addImport("gsl_adapter", gsl_mod);
test_exe_root.addImport("arrow_adapter", arrow_mod);
```

This means tests can exercise the full dependency chain — e.g., a formula test can construct a formula, register it, resolve its dependencies, execute via the arrow adapter, and collect results in a ResultFrame.

### Test Filtering

To run a single test or a subset:

```bash
zig build test --filter "dep-resolve/basic"
```

## Quality And Security Gates

- **Formatting**: `zig fmt --check` validates Zig source files. Fix with `zig fmt`.
- **Sanitizers**: Build with `-Doptimize=ReleaseSafe` to enable Zig's built-in safety checks (undefined behavior, integer overflow, out-of-bounds access).

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
