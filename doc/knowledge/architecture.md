# Yamori — Architecture

**Language-agnostic specification.** Describes what Yamori is, what it receives, what it decides, how the pieces fit together, and how domains compose. Notation is pseudo-schema, not any one language. Implementation details and tooling choices live in execution plans; the methodology each domain implements is described in strategy and milestone documents.

---

## 1. The Architecture Thesis

Financial computation already has excellent libraries. The problem is that they exist as separate islands, each with its own API, types, memory model, ownership rules, error handling, threading model, build system, versioning, language bindings, and platform peculiarities. A sophisticated financial application therefore ends up building its own integration layer — and many organizations independently recreate some version of that infrastructure.

Yamori exists to build that layer once.

```text
Application
    │
    ▼
  Yamori
    │
    ├── financial formula dependency graph
    ├── valuation engine
    ├── technical analysis
    ├── portfolio analytics
    ├── derivatives pricing
    └── advanced analytics
          │
          ▼
   best available
   native engines
```

Yamori is a **native quantitative-computing runtime** that unifies mature specialized libraries behind **one stable C ABI and one shared data model**. It does **not** implement numerical or financial algorithms — there is no NumPy, no SciPy, no TA-Lib, no QuantLib inside Yamori. It owns the contract — the API, the ABI, the types, the memory model, the ownership semantics, the routing, the execution policy, the errors, the versioning, the testing, and the distribution. The backends own the algorithms.

### 1.1 The Core Advantage

Yamori's structural advantage is a combination of four things — any one by itself is insufficient; together they are the product:

```text
ONE API
+ ONE ABI
+ ONE MEMORY MODEL
+ BACKEND ROUTING
```

- **One API.** The user sees a coherent namespace (`yamori.array`, `yamori.linalg`, `yamori.timeseries`, `yamori.ta`, `yamori.optimize`, `yamori.integrate`, `yamori.options`, `yamori.curves`, `yamori.risk`) that describes problems, not implementations.
- **One ABI.** A stable C interface exposes all runtime capabilities. Language bindings remain thin: Python, Zig, Rust, C++, Go, Java, C# — all connect to the same runtime.
- **One memory model.** A common representation for numeric and columnar data (`Buffer` → `Array` → `Series` → `Table`) so that backend adaptation is primarily a matter of constructing views rather than copying datasets.
- **Backend routing.** Every Yamori function is a semantic operation that routes through a capability registry to the appropriate backend engine. The invocation flow is: semantic validation → backend resolution → zero-copy view/adaptation → backend execution → error normalization → Yamori result.

### 1.2 Product Principles

**Own semantics. Delegate implementation.** Yamori owns the contract — the API, the ABI, the types, the memory model, the ownership semantics, the routing, the execution policy, the errors, the versioning, the testing, and the distribution. Backends own the algorithms. Exceptions to this rule require concrete justification: no suitable upstream implementation exists, a critical interoperability requirement demands it, a significant performance advantage is provable, or a backend-independent primitive is needed. Yamori does not reimplement matrix multiplication, linear algebra, integration, technical indicators, or financial models — those are delegated to BLAS/LAPACK, Cuba, TA-Lib, QuantLib, and similar engines.

**Composition before coverage.** The objective is not to support 10,000 functions. It is to make 100 important functions from ten different domains compose correctly over one representation. Market prices → returns → rolling volatility → model calibration → option valuation → scenario risk — all stages operating over Yamori objects without backend-specific conversion code.

**Avoid backend leakage.** Yamori functions accept and return Yamori types, never backend types. `yamori.ta.macd()` returns a Yamori Series, not a GSL vector. Backend representations remain private.

**Native first, Python excellent.** Python is an important frontend with ergonomic bindings, but the runtime does not embed or depend on Python. Python is the ergonomic interface, not the architectural owner.

**Delegate algorithms. Own the contract.** Yamori does not reimplement numerical or financial algorithms. There is no NumPy inside Yamori, no SciPy, no TA-Lib, no QuantLib. Every algorithm — matrix multiplication, singular value decomposition, Monte Carlo integration, spectral analysis, Black-Scholes pricing, moving averages — is delegated to the appropriate backend. Yamori's job is to make those backends compose over one representation, one ABI, and one memory model. This is the principle that distinguishes Yamori from every other quantitative library.

---

## 2. Runtime Foundation

Yamori's durable runtime capabilities form the foundation for all domain functionality.

### 2.1 Financial Formula Dependency Graph

Financial metrics are defined as named dependency graphs over source metrics. Derived metrics resolve in deterministic topological order without performing numerical work themselves.

```text
NamedFormulaNode
  name        : String                 # unique identifier within the graph
  dependencies: List<String>           # names of required source metrics
  backend     : BackendHandle          # resolves to a specific engine
  params      : Map<String, DataPoint> # parameter values at graph-evaluation time
```

The graph enables sensitivity analysis, Monte Carlo simulation, and reverse DCF because `runValuation()` traverses the graph rather than calling a monolithic function. This is Yamori's strongest differentiator: the graph, not any single formula, is the reusable asset. Each domain registers its operations as named nodes. The same graph serves valuation formulas, technical indicators, portfolio operations, integration routines, and pricing functions.

### 2.2 Unified Backend Router

Every direct library invocation flows through one stable semantic dispatch layer. The router registers backend functions behind a capability registry that maps each Yamori operation to its backend implementation.

```text
BackendRegistry
  registrations : Map<OperationId, BackendBinding>

BackendBinding
  capability    : OperationId            # e.g. "linalg.gemm", "ta.macd"
  engine        : BackendHandle          # BLAS, TA-Lib, QuantLib, etc.
  params        : ParamSchema            # required parameters for this operation
  output_type   : YamoriType             # result type descriptor
```

The router normalizes backend failures into Yamori statuses, prevents C++/native types from leaking through Yamori's public surface, and enables backend plurality — eventually multiple engines may implement the same semantic operation, selected by platform, CPU capabilities, datatype, input size, or configured preference.

### 2.3 Shared-Memory Representation

The same financial arrays and tables are mapped by multiple processes with Arrow-compatible layout. Offset-based buffer descriptors (`workspace ID` + `buffer offset` + `byte length`) rather than process-local pointers enable zero-copy process attach for cross-process data sharing.

#### 2.3.1 Data Model

```text
Buffer
  workspace_id  : WorkspaceId            # identifies a shared-memory region
  offset        : Int64                  # byte offset within workspace
  length        : Int64                  # byte length
  datatype      : YamoriDataType         # float64, int32, bool, etc.

Array
  buffer        : Buffer                 # underlying storage
  shape         : List<Int64>            # dimensions
  strides       : List<Int64>            # byte offsets per dimension
  alignment     : Int64                  # memory alignment requirement
  ownership     : Enum{ Owned, Borrowed, Foreign }
  lifetime      : LifetimeDescriptor     # who owns, who may access

Series
  array         : Array                  # inherits all array fields
  validity      : Optional<Bitmap>       # null/missing indicator per element
  logical_type  : YamoriDataType         # may differ from physical type
  metadata      : Map<String, String>    # column-level annotations

Table
  schema        : Schema                 # column names, types, metadata
  columns       : List<Series>           # columns share workspace when possible
  validity      : Optional<Bitmap>       # row-level validity
```

For columnar data, Arrow's C Data Interface provides the interoperability model where practical — a language-independent columnar representation and a C Data Interface specifically designed for cross-runtime, zero-copy exchange over a shared C ABI.

#### 2.3.2 Shared Memory

```text
Process A
    │
    ▼
┌──────────────────────────────┐
│ shared-memory workspace      │
│                              │
│ schema                       │
│ column descriptors           │
│ validity bitmaps             │
│ value buffers                │
│ metadata                     │
└──────────────────────────────┘
    ▲
    │
Process B
```

Each process resolves offsets against its local mapping. This creates a common data plane suitable for market data, analytics, pricing, risk, plugins, terminals, and worker processes without serialization for trusted local pipelines.

### 2.4 C ABI

A language-neutral interface that exposes all runtime capabilities through C-callable functions. Uses Arrow C Data Interface structures for array/table interchange and provides opaque handles for backend state.

```c
// Data interchange (Arrow C Data Interface compatible)
ym_array_from_arrow(struct ArrowArray*, struct ArrowSchema*);
ym_array_to_arrow(ym_handle_t, struct ArrowArray*, struct ArrowSchema*);

// Core operations
ym_array_mul(ym_handle_t input, float scalar, ym_handle_t* result);
ym_array_cumsum(ym_handle_t input, ym_handle_t* result);

// Domain operations
ym_valuation_run(ym_handle_t inputs, ym_handle_t policy, ym_handle_t* result);
ym_ta_macd(ym_handle_t close, int fast_period, int slow_period, int signal_period, ym_handle_t* result);
ym_option_price(ym_handle_t params, ym_handle_t* result);

// Workspace and memory
ym_workspace_create(int size, ym_handle_t* workspace);
ym_workspace_attach(ym_handle_t workspace, ym_handle_t* attached);

// Status and errors
ym_status_code ym_last_status();
const char* ym_status_message(ym_status_code);

// Handle management
typedef void* ym_handle_t;
ym_handle ym_handle_create(void);
void ym_handle_destroy(ym_handle_t);
```

ABI compatibility tests detect accidental binary-interface breakage across releases.

### 2.5 Deterministic Execution Policy

Pins algorithms, pins RNG with explicit seed, enforces deterministic threading policy, specifies reduction order, and disables fast-math. Produces bit-identical results across Linux x86, Linux ARM, macOS ARM, and Windows x86. Every downstream milestone depends on this.

**The rules:**

1. **Iterated multiplication for discount factors.** Never use a power function for `(1 + r)^t`. Power functions are not correctly rounded and vary across math library versions and platforms; iterated multiplication is bit-identical everywhere. This is the single rule that removes the most likely source of cross-machine divergence.

2. **No fast-math or fused-multiply-add contraction** where the unfused form is the specified arithmetic.

3. **Fixed summation order.** Present values accumulate from the first year forward. No parallel reduction in any path reaching a reported number.

4. **Fixed iteration counts in solvers**, not tolerance-based early exits. Tolerance-based early exits are not portable.

5. **No unordered-container iteration** in numeric paths.

6. **Counter-based RNG.** Draw *i* for variable *j* is a pure function of seed, *i*, and *j*. With a sequential generator, parallelism and reproducibility are mutually exclusive.

7. **Single-threaded execution policy** by default. Parallel paths that reach reported numbers must produce the same reduction order on any thread count.

**The hash identity:** Every result carries a `provenance_hash = BLAKE3(canonical(inputs) ‖ policy ‖ semver ‖ dataset manifest)`. Two runs agreeing on the hash must agree on every output number. Golden tests assert on the hash rather than on individual figures.

---

## 3. Backend Library Routing

| Library | Domain | Capabilities |
|---------|--------|-------------|
| **Apache Arrow C++** | All | Canonical memory representation, CSV I/O, compute registry, cross-language interchange, columnar operations |
| **GNU GSL** | Valuation | Statistics (medians, outlier filtering), interpolation (transition paths), roots (reverse DCF bisection), RNG (Monte Carlo) |
| **TA-Lib** | Technical Analysis | Moving averages (SMA, EMA, WMA, DEMA, TEMA, KAMA, MAMA, T3), oscillators (RSI, Stochastic, CCI, ROC, MOM), volatility (Bollinger Bands, ATR, ADX, SAR), volume (OBV, AD, ADOSC), candlestick patterns |
| **QuantLib** | Options & Derivatives | Options pricing (European, American, exotic), fixed income (bonds, swaps, cap/floor), numerical methods (Monte Carlo, finite-difference, trees), volatility surfaces, yield curve construction |
| **BLAS + LAPACK** | Portfolio Analytics | Vector/matrix operations (GEMM, axpy, dot), eigenvalue decomposition (DSYEVD), SVD (DBDSDC), Cholesky (DPOTRF), QR (DGEQRF), linear solvers |
| **Cuba** | Advanced Analytics | Multidimensional Monte Carlo (Vegas, Suave), deterministic adaptive integration (Divonne, Cuhre) |
| **FFTW** | Advanced Analytics | Fast Fourier transforms (real/complex DFT, DCT, DST, multi-dimensional transforms, plan-based execution) |

A new library enters Yamori only when a domain requires capabilities the current backends do not provide — not because the library happens to be useful.

### 3.1 Invocation Flow

```
function call
     │
     ▼
semantic validation          // types, ranges, dependencies
     │
     ▼
backend resolution           // registry lookup, plurality selection
     │
     ▼
zero-copy view/adaptation    // construct backend view over Yamori buffer
     │
     ▼
backend execution            // delegate to the engine
     │
     ▼
error normalization          // backend status → Yamori status
     │
     ▼
Yamori result                // result in Yamori types
```

### 3.2 Backend Plurality

Eventually multiple engines may implement the same semantic operation:

```text
matrix multiply
│
├── OpenBLAS
├── BLIS
├── vendor BLAS
└── accelerator backend
```

Selection depends on platform, CPU capabilities, datatype, input size, requested determinism, available accelerator, or configured backend. The API remains unchanged. Yamori becomes a **stable front end to an evolving backend ecosystem**.

---

## 4. Multi-Domain Architecture

All domains share the same runtime. Each installs as a set of named formula nodes on the dependency graph, registered through the backend router.

### 4.1 Runtime Foundation

**Purpose.** The dependency graph, backend router, shared-memory representation, C ABI, and deterministic execution policy — the infrastructure that makes Yamori a composable runtime rather than a single-domain calculator.

**Key types:** `NamedFormulaNode`, `BackendRegistry`, `Buffer`, `Array`, `Series`, `Table`, `Workspace`, `ValuationPolicy`.

**Key functions:** `graph.resolve()`, `router.dispatch()`, `array.mul()`, `workspace_create()`, `run_valuation()`.

### 4.2 Valuation Engine

**Purpose.** A working Damodaran-style FCFF discounted cash flow engine that accepts financial statements and policy inputs and produces a per-share intrinsic value estimate.

**Key types:** `ValuationInputs`, `ValuationPolicy`, `ValuationResult`, `Money<C>`, `Rate`, `Period`, `DataPoint<T>`, `FinancialPeriod`, `MarketData`, `EquityClaims`, `GeoExposure`, `CostOfCapital`, `GrowthPath`, `TerminalValue`, `EquityBridge`, `ImpliedGrowth`, `AuditResult`.

**Key functions:** `runValuation(inputs, policy) → result | Error` — the pure, re-enterable core function.

**Pipeline stages:**
```text
ingest ──► resolve ──► adjust ──► derive ──► project ──► analyse ──► audit
```

**Decision rules:** Source priority (filing > provided statement > calculated metric > earnings report > analyst consensus > external database). Sector selection by company domicile, not listing venue. Base-year distortion detection (negative operating income or margin deviation > 30% from median). R&D and lease capitalization as all-or-nothing adjustments. Beta from bottom-up relever (or regression fallback). Country risk netted against base market. Growth from sustainable ROIC × reinvestment, transition by linear interpolation, stable by `min(risk-free, inflation + real growth)`. Tax rate converges from effective to statutory over projection years. Discount factors by iterated multiplication. Terminal value by Gordon growth (primary) and exit multiple (cross-check). Reverse DCF by fixed-count bisection (100 iterations). Monte Carlo via counter-based RNG with fixed seed.

**Audit severities:** Error (blocks rendering), Warn (strain indicators), Info (conventions). Errors cover: stable growth within risk-free rate, WACC − g ≥ 100bp, currency consistency, CRP derived from default spreads (not raw), terminal value share < 75%, adjustments propagated completely, country risk netted, equity compensation handled exactly once.

### 4.3 Financial Statement Ingestion

**Purpose.** Data integrity layer between raw financial filings and the cleaned inputs required by the valuation engine.

**Key types:** `XbrlElement`, `SourceId`, `DatasetManifest`, `NormalizedPeriod`.

**Key epics:** XBRL mapping (US-GAAP and IFRS to canonical names), R&D capitalization (amortizing asset, sector-dependent periods), lease capitalization (discount-rate present value), stock-based compensation deduction (Black-Scholes option valuation, treasury-method fallback), base-year normalization with distortion detection, TTM calculation and source-priority resolution.

**Invariant.** Every adjusted metric carries provenance tracing to the source filing and specific adjustment applied.

### 4.4 Cross-Checks, Sensitivity, and Monte Carlo

**Purpose.** Transforms a single deterministic valuation into a bounded, auditable range with probabilistic confidence intervals.

**Key epics:** Reverse DCF (fixed-count bisection solver solving `DCF(g_high) − market_price = 0`). Relative-multiple cross-checks (implied P/E, P/S, EV/EBITDA). Sensitivity matrices (WACC/growth grid over the dependency graph). Scenario analysis (bull/base/bear/stress input sets with base-case preservation). Audit checks (severity-flagged assertions). Monte Carlo: random sampling (seeded distributions with hard constraints), runner (thousands of sampled inputs through `runValuation()`), summary (percentiles P5/P25/P50/P75/P95, valuation range), demo (end-to-end CSV → DCF → MC distribution).

### 4.5 Comparative Analysis, Reports, and Historical Replay

**Purpose.** Extends single-company valuation to multi-company comparative analysis with exportable reports, historical replay, and deterministic audit trails.

**Key epics:** Peer-set management (sourced inputs, canonical identifiers, persistent sector assignments). Batch valuation (shared policy objects, zero-copy across runs). Valuation report generation (machine-readable JSON with structured narrative). Historical replay and backtesting (same pipeline, same historical data → same results). Deterministic audit trail and provenance hash (`BLAKE3(canonical(inputs) ‖ policy ‖ semver ‖ dataset manifest)`). Dataset versioning and manifest management (SHA-256 checksums, vintage tracking). CLI and export interfaces. Relative valuation metrics (discount/premium to peer median, percentile ranks). Sector-relative positioning (WACC/ROIC/growth vs sector medians).

**Key invariant.** Running any batch twice with the same inputs produces bit-identical results for every company.

### 4.6 Technical Analysis

**Purpose.** First domain proving the runtime generalizes beyond valuation. Integrates TA-Lib and builds the indicator formula framework.

**Library:** TA-Lib.

**Key epics:** TA-Lib integration and indicator registry. Moving averages (SMA, EMA, WMA, DEMA, TEMA, KAMA, MAMA, T3). Oscillators (RSI, Stochastic, CCI, ROC, MOM). Volatility and trend (Bollinger Bands, ATR, ADX, SAR). Volume indicators and pattern recognition (OBV, AD, ADOSC, candlestick patterns). Cross-domain demo (price series → MAs → oscillators → volatility → volume through the same graph).

**Key insight.** Technical indicators on the same data as a valuation produce no cross-domain interference — they share the graph but use independent node sets.

### 4.7 Portfolio Analytics

**Purpose.** Matrix-heavy computation where shared memory becomes operationally essential. Integrates BLAS and LAPACK.

**Libraries:** BLAS, LAPACK.

**Key epics:** BLAS/LAPACK integration and linear algebra registry. Covariance estimation (sample, rolling, EWMA, Ledoit-Wolf shrinkage). Factor models (PCA via SVD, factor regression via OLS/normal equations). Risk decomposition (factor/asset/marginal contributions, component VaR, risk parity). Portfolio optimization (Markowitz, min variance, max Sharpe, risk parity, Black-Litterman, constrained). Portfolio simulation and scenario analysis (historical + MC scenarios with BLAS-accelerated operations). Historical scenario analysis and backtesting.

**Key insight.** This is where Yamori's shared-memory infrastructure becomes operationally essential — covariance matrices for large portfolios (100+ assets) must be shared across optimization, risk decomposition, and simulation processes without copying.

### 4.8 Advanced Analytics

**Purpose.** High-dimensional integration and spectral analysis — the last major class of numerical methods that financial computation requires. Integrates Cuba and FFTW.

**Libraries:** Cuba, FFTW.

**Key epics:** Cuba/FFTW integration and combined registry. Monte Carlo integration (Vegas/Suave for high-dimensional probability spaces). Deterministic integration (Divonne/Cuhre for smooth integrands requiring high precision). FFT spectral analysis (real/complex DFT, DCT, DST, cycle detection). Spectral filtering and cycle decomposition (bandpass filtering, noise removal, dominant period identification). Cross-domain demo (all five domains operating independently on the same graph).

**Key insight.** Five domains — valuation, technical analysis, derivatives, portfolio analytics, advanced analytics — four library families (TA-Lib, QuantLib, BLAS/LAPACK, Cuba+FFTW), one dependency graph, one backend router, one deterministic execution policy.

### 4.9 Options and Derivatives

**Purpose.** Handles closed-form and numerically-intensive pricing. Integrates QuantLib.

**Library:** QuantLib.

**Key epics:** QuantLib integration and pricing registry. Equity options (European via Black-Scholes-Merton, American via binomial trees). Exotic options (barriers, Asians, lookbacks, compounds via MC and finite-difference). Fixed income instruments (zero-coupon, coupon-bearing bonds, swaps, caps/floors, swaptions). Volatility surface and yield curve management (bootstrapped, interpolated, shared-memory objects). Cross-domain demo (option pricing → exotic → fixed income → surfaces → curves through the same graph).

**Key insight.** Fixed income yield curve infrastructure provides yield curve data useful for Damodaran cost-of-debt and risk-free rate lookups, demonstrating cross-domain utility.

---

## 5. Cross-Domain Composition

All domains share the same runtime. A single Yamori representation can flow through multiple domains:

```text
CSV / Arrow data
       │
       ▼
financial series
       │
       ├── valuation & adjustments
       ├── cross-checks, Monte Carlo, sensitivity
       ├── comparative analysis, reports, historical replay
       ├── technical indicators (price series)
       ├── factor models, risk, optimization (returns series)
       ├── multidimensional integration, spectral analysis
       └── options pricing, fixed income, vol surfaces (underlying, rate, vol)
```

The dependency graph serves all domains. Each domain registers its operations as named nodes. The same backend router, shared-memory representation, C ABI, and deterministic execution policy apply uniformly. No domain duplicates the foundation layer.

### 5.1 Composition Patterns

```text
market data
     │
     ▼
returns (Arrow compute)
     │
     ├── volatility (TA-Lib Bollinger Bands, rolling std)
     ├── factor model (BLAS covariance, LAPACK PCA)
     └── option input (QuantLib vol surface from realized vol)
```

The same covariance matrix computed from Damodaran-adjusted fundamentals feeds into portfolio optimization. The same yield curve from QuantLib feeds Damodaran cost-of-debt. The same spectral decomposition feeds both cycle detection and signal filtering.

---

## 6. The Moat

Yamori's defensibility is not function count. Function counts are easy to copy and specialized libraries will nearly always have deeper coverage. The moat is structural:

```text
common data representation
zero-copy adaptation
stable semantic contracts
shared-memory architecture
backend routing
error normalization
deterministic execution policy
cross-platform backend builds
dependency compatibility
ABI stability
test vectors across backend upgrades
language bindings generated from one ABI
```

If Yamori becomes merely a collection of wrappers, there is little reason for it to exist. If it becomes the **standard data plane and execution contract through which heterogeneous quantitative engines compose**, it solves a substantially harder problem.

---

## 7. Audit and Observability

### 7.1 Deterministic Audit Trail

Every valuation carries a complete audit trail: dataset manifest hashes, policy field values, source document citations, adjustment decisions, and provenance chains for every computed metric. The `provenance_hash = BLAKE3(canonical(inputs) ‖ policy ‖ semver ‖ dataset manifest)` enables machine-checkable reproducibility — any third party can verify the hash against their own computation. Golden tests assert on provenance hashes, not just numeric outputs.

### 7.2 Observability Surface

Phase 0 exposes runtime state through CLI output and in-memory snapshots. Every pipeline stage reports completion states, metric counters, and diagnostic signals:

| Signal | Stage | Meaning |
|--------|-------|---------|
| Validated records | ingest | Financial periods and market data accepted |
| Source conflicts | resolve | Competing values for the same element |
| Data gaps | resolve | Required fields absent from all sources |
| R&D capitalized | adjust | Capitalization adjustment applied |
| Leases capitalized | adjust | Lease capitalization applied |
| ROIC window | derive | Trailing years used for statistics |
| Growth stages | derive | High-growth + transition + terminal years |
| Projected years | project | Forward projection horizon |
| Sensitivity runs | analyse | Grid cells re-evaluated |
| Scenario runs | analyse | Named scenarios executed |
| Reverse DCF solves | analyse | Bisection iterations for implied growth |
| Audit checks | audit | Total checks, by severity |
| Gold hash | audit | BLAKE3 provenance hash |

### 7.3 Failure Transparency

Failures are not silent. The `!Error` convention (no `unreachable` in library code, no silent fallback values) ensures that if a pipeline stage cannot produce a result, the error is returned and the calling stage reports the gap. Failure categories include: missing required periods, unresolved source conflicts, negative operating income with negative median margin, stable growth exceeding risk-free rate, WACC minus stable growth below 100bp, terminal value numerically unstable, currency mismatch, SBC double-counting, partial capitalization, and dataset checksum mismatch.

### 7.4 Alerting Policy

Future alerting should use a bounded severity taxonomy:

| Severity | Meaning |
|----------|---------|
| `critical` | Data integrity failure, audit Error verdict, dataset checksum mismatch, or valuation blocking rendering |
| `warning` | Degraded data quality, sustained gap count, terminal value share >75%, or methodology warnings |
| `info` | Non-paging operational signal for awareness, provenance correlation, or audit trails |

---

## 8. Boundary: What Yamori Is and Is Not

### 8.1 What Yamori Is

- A native quantitative-computing runtime
- A composability layer that unifies best-in-class libraries behind one stable ABI and one shared data model
- The contract — the API, the ABI, the types, the memory model, the ownership semantics, the routing, the execution policy, the errors, the versioning, the testing, and the distribution
- One integration → many quantitative capabilities
- A stable front end to an evolving backend ecosystem
- The portability, interoperability, and composition layer between applications and the fragmented native quantitative ecosystem

### 8.2 What Yamori Is Not

| Not | Because |
|-----|---------|
| Another NumPy implementation | NumPy's C API requires Python; Yamori's C ABI is language-neutral. Yamori delegates array operations to Arrow, not reimplements them. |
| Another SciPy | SciPy delegates to C/C++/Fortran — Yamori's contribution is runtime composition, not algorithm implementation. Yamori does not reimplement optimization, integration, interpolation, linear algebra, or statistical functions. |
| Another pandas | pandas' index alignment semantics would conflict with predictable native execution. Yamori delegates tabular compute to Arrow. |
| Another Polars | Polars is the best DataFrame query engine; Yamori does not compete on DataFrame execution alone. DataFrames are one capability inside Yamori, not its reason for existence. |
| Another PyMC | PyMC is probabilistic programming (Bayesian inference); Yamori's Monte Carlo is lower-level and broader, delegated to Cuba. |
| Another QuantLib | QuantLib is a comprehensive derivatives framework; it is one backend inside Yamori. Yamori does not reimplement pricing engines. |
| A wrapper collection | Wrappers are trivially copied; the moat is data representation, routing, shared-memory architecture, determinism, and error normalization. Yamori owns the contract; backends own the algorithms. |

### 8.3 What Yamori Does Not Reimplement

Yamori deliberately does **not** reimplement the following categories of algorithms, which are delegated to backend libraries:

- **Linear algebra** — matrix multiplication, SVD, Cholesky, eigenvalue decomposition, linear solvers → BLAS / LAPACK
- **Monte Carlo & integration** — multidimensional integration, quasi-random sequences, stochastic simulation → Cuba
- **Fast Fourier transforms & spectral analysis** — DFT, DCT, DST, cycle detection → FFTW
- **Technical indicators** — moving averages, oscillators, volatility measures, volume indicators, candlestick patterns → TA-Lib
- **Financial models** — option pricing (European, American, exotic), fixed income, volatility surfaces, yield curve construction → QuantLib
- **Statistics** — medians, outlier filtering, interpolation, root finding, random number generation → GNU GSL

The only algorithms Yamori implements are those that serve the composition layer itself: the dependency graph resolver, the backend router, the error normalization pipeline, the deterministic execution policy, the shared-memory buffer descriptor system, the provenance hash computation, and the data model type constructors (Buffer, Array, Series, Table). Everything computational is delegated.

---

## 9. Strategic Flywheel

If the architecture works, each additional backend increases the value of every frontend:

```text
new backend
      │
      ▼
Yamori C ABI
      │
      ├── immediately usable from Python
      ├── immediately usable from Zig
      ├── immediately usable from Rust
      └── immediately usable from C++, Go, Java, C#, ...
```

And each new frontend increases the value of every backend. This creates a two-sided technical flywheel:

```text
            more backends
                 ▲
                 │
                 │
more languages ◄─┼─► more capabilities
                 │
                 ▼
        stronger common ABI
```

That is a fundamentally different ecosystem model from a language-specific package.

---

## 10. Long-Term Position

```text
          Quantitative application
                   │
                   ▼
                Yamori
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
 numerical      analytics    finance
 engines         engines      engines
```

Yamori sits between applications and the fragmented native quantitative ecosystem. It is the **portability, interoperability and composition layer**.

---

## Cross-References

- Product bet, target user, and priority stack: [`doc/strategy/positioning.md`](../strategy/positioning.md)
- Supported capabilities and backend library table: [`doc/strategy/capabilities.md`](../strategy/capabilities.md)
- Execution plans: [`doc/execution/plans/`](../execution/plans/)
- Observability surface: [`doc/execution/observability.md`](../execution/observability.md)
- Telemetry semantics: [`doc/execution/telemetry.md`](../execution/telemetry.md)
- Coding conventions: [`doc/execution/contribution/yamori.md`](../execution/contribution/yamori.md)
