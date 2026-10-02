# Yamori — Supported Capabilities

## Positioning

Yamori is a native financial computation runtime that unifies mature specialized libraries behind one stable ABI and shared data model.

It does not implement financial or numerical algorithms itself. It owns the contract — the API, the ABI, the types, the memory model, the ownership semantics, the routing, the execution policy, the errors, the versioning, the testing, and the distribution. The backends own the algorithms.

A user chooses Yamori when they need:

```text
one integration
→ many quantitative capabilities
```

rather than:

```text
application
├── Arrow wrapper
├── GSL wrapper
├── TA-Lib wrapper
├── QuantLib wrapper
├── BLAS/LAPACK wrapper
├── Cuba wrapper
├── FFTW wrapper
├── conversions
├── error translation
├── lifetime management
├── build scripts
└── platform-specific packaging
```

---

## Runtime Capabilities

These are domain-independent capabilities that exist before any financial domain ships. Every domain milestone depends on them.

| Capability | Milestone | Epic | Description |
|---|---|---|---|
| **Financial formula dependency graph** | M1 | V1.1 | Named formulas as nodes over source metrics. Derived metrics resolve in deterministic topological order without performing numerical work themselves. Enables sensitivity analysis, Monte Carlo simulation, and reverse DCF because evaluation traverses the graph rather than calling a monolithic function. |
| **Unified backend router** | M1 | V1.2 | Every direct library invocation flows through one stable semantic dispatch layer. Registers Arrow compute functions, GSL adapters, and external library backends behind a capability registry that maps each Yamori operation to its backend implementation. Normalizes backend failures into Yamori statuses and prevents backend types from leaking through Yamori's public surface. |
| **Shared-memory representation** | M1 | V1.3 | Same financial arrays and tables mapped by multiple processes with Arrow-compatible layout. Uses offset-based buffer descriptors (workspace ID + buffer offset + byte length) rather than process-local pointers. Enables zero-copy process attach for cross-process data sharing. |
| **C ABI** | M1 | V1.4 | Language-neutral interface exposing all runtime capabilities through C-callable functions. Uses Arrow C Data Interface structures for array/table interchange. Provides opaque handles for backend state. ABI compatibility tests detect accidental binary-interface breakage across releases. |
| **Deterministic execution policy** | M1 | V1.5 | Pins algorithms, pins RNG with explicit seed, enforces deterministic threading policy, specifies reduction order, disables fast-math. Produces bit-identical results across Linux x86, Linux ARM, macOS ARM, and Windows x86. Every downstream milestone depends on this. |

---

## Valuation Capabilities (Damodaran)

The first and primary financial domain. Every capability traverses the same dependency graph built in M1.

### M2: Damodaran Valuation Engine

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| Core valuation runner | V2.1 | Arrow + GSL | Adjusted financial statements, policy inputs | `runValuation()` graph traversal |
| Historical metrics & ROIC | V2.2 | Arrow + GSL | Revenue, EBIT, balance-sheet series | NOPAT, invested capital, ROIC, reinvestment rate, outlier-filtered sustainable inputs |
| Cost of capital & WACC | V2.3 | Arrow + GSL | Sector unlevered beta, D/E, geographic revenue split, synthetic rating | Bottom-up beta, revenue-weighted CRP, cost of equity, cost of debt, WACC |
| Three-stage growth & FCFF projection | V2.4 | Arrow + GSL | Sustainable ROIC, sustainable reinvestment rate | High-growth rate, transition paths (10-year), FCFF schedule |
| Terminal value & per-share value | V2.5 | Arrow + GSL | FCFF schedule, WACC, terminal growth rate, debt/cash/non-operating assets | Intrinsic value per share, terminal value share |

### M3: Financial Statement Ingestion

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| XBRL mapping | V3.6 | Arrow (CSV) | XBRL filings (US-GAAP, IFRS) | Normalized typed internal representation with provenance |
| R&D capitalization | V3.7 | Arrow + GSL | EBIT, R&D expense, sector | Amortizing R&D asset, adjusted EBIT, adjusted invested capital |
| Lease capitalization | V3.8 | Arrow + GSL | Operating lease obligations, discount rate | Capitalized lease obligations, adjusted EBIT, adjusted debt |
| SBC deduction | V3.9 | Arrow + GSL | Stock-based compensation, outstanding options | SBC as operating expense, diluted share count, option fair value |
| Base-year normalization | V3.10 | Arrow + GSL | Five-year historical margins, current period | Normalized EBIT, distortion detection report |
| TTM & source priority | V3.11 | Arrow + GSL | Fiscal-year data, multiple filing sources | Trailing-twelve-month metrics, resolved source citation |

### M4: Cross-Checks & Monte Carlo

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| Reverse DCF | V4.12 | GSL (Roots) | Market price, all other DCF assumptions fixed | Implied Stage 1 growth rate |
| Relative-multiple cross-checks | V4.13 | Arrow | Intrinsic equity value, EBITDA, shares | Implied P/E, P/S, EV/EBITDA, exit-multiple terminal value |
| Sensitivity matrices | V4.14 | Arrow + GSL | WACC range, growth range grid | Intrinsic value matrix (deterministic, reproducible) |
| Scenario analysis | V4.15 | Arrow | Bull/base/bear/stress input sets | Scenario distribution with base-case preservation |
| Audit checks | V4.16 | Arrow | All valuation outputs | Severity-flagged assertions (Error/Warn/Info) |
| Random sampling | V4.17 | GSL (RNG) | Seed, distribution specs, hard constraints | Reproducible samples for growth, margin, WACC, ROIC |
| Monte Carlo runner | V4.18 | Arrow + GSL | N sampled input sets, `runValuation()` | N intrinsic values with invalid-sample handling |
| Monte Carlo summary | V4.19 | GSL (Statistics) | N intrinsic values | Mean, stddev, median, P5/P25/P50/P75/P95, valuation range |

### M5: Comparative Analysis & Reports

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| Peer-set management | V5.21 | Arrow | Company identifiers, sector assignments | Managed peer sets, canonical identifiers, consistent sector assignments |
| Batch valuation | V5.22 | Arrow | Peer set, shared policy objects | Per-company valuation table with all M2/M3/M4 outputs |
| Valuation reports | V5.23 | Arrow | M2-M4 outputs, methodology assumptions | Structured JSON + narrative report with full provenance |
| Historical replay | V5.24 | Arrow | Historical financial data, past dates | Historical intrinsic values, bit-identical reproducibility |
| Audit trail | V5.25 | Arrow | Dataset manifest, policy, adjustments | BLAKE3 provenance hash, deterministic audit chain |
| Dataset versioning | V5.26 | Arrow | Dataset files | SHA-256 manifest, version tracking, refresh detection |
| CLI interface | V5.27 | — | JSON input, dataset manifest | JSON output, MCP server contract |
| Relative valuation metrics | V5.28 | Arrow | Peer-set valuations | Discount/premium to peer median, percentile ranks |
| Sector-relative positioning | V5.29 | Arrow | Peer-set results, sector benchmarks | WACC/ROIC/growth vs. sector medians, deviation flags |

---

## Technical Analysis Capabilities

First post-M4 domain. Proves the runtime generalizes beyond valuation.

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| Indicator registry | V6.1 | TA-Lib | — | TA-Lib function handles mapped to Yamori identifiers |
| Moving averages | V6.2 | TA-Lib | Price series, period | SMA, EMA, WMA, DEMA, TEMA, KAMA, MAMA, T3 |
| Oscillators | V6.3 | TA-Lib | Price series, period | RSI, Stochastic, CCI, ROC, MOM |
| Volatility & trend | V6.4 | TA-Lib | OHLCV series | Bollinger Bands, ATR, ADX, Parabolic SAR |
| Volume & patterns | V6.5 | TA-Lib | OHLCV series | OBV, AD, ADOSC, candlestick pattern signals |

---

## Options & Derivatives Capabilities

Second post-M4 domain. Handles closed-form and numerically-intensive pricing.

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| Pricing registry | V7.1 | QuantLib | — | QuantLib pricing engines mapped to Yamori identifiers |
| Equity options | V7.2 | QuantLib | Underlying, strike, maturity, vol, dividend, rate | Fair value, Delta/Gamma/Vega/Theta/Rho (closed-form + tree) |
| Exotic options | V7.3 | QuantLib | Same + barriers, averages, lookback | Monte Carlo/finite-difference pricing with Greeks |
| Fixed income | V7.4 | QuantLib | Cash flows, yield curve, day-count | Bond prices, swap NPV, caps/floors, yield curve |
| Vol surfaces & curves | V7.5 | QuantLib | Market quotes, fitting method | Implied vol surfaces, bootstrapped yield curves |

---

## Portfolio Analytics Capabilities

Third post-M4 domain. Matrix-heavy computation where shared memory becomes operationally essential.

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| Linear algebra registry | V8.1 | BLAS/LAPACK | — | BLAS/LAPACK handles mapped to Yamori identifiers |
| Covariance estimation | V8.2 | BLAS | Return series | Sample/rolling/ewma covariance, Ledoit-Wolf shrinkage |
| Factor models | V8.3 | BLAS + LAPACK | Return series, factor definitions | PCA components, factor loadings, residuals |
| Risk decomposition | V8.4 | LAPACK | Covariance, portfolio weights | Factor/asset/marginal contributions, component VaR |
| Portfolio optimization | V8.5 | LAPACK | Expected returns, covariance, constraints | Optimized weights, Sharpe, constraint status |
| Portfolio simulation | V8.6 | BLAS + GSL | Weights, scenarios, RNG seed | Portfolio value distributions, drawdown analysis |

---

## Advanced Analytics Capabilities

Fourth post-M4 domain. High-dimensional integration and spectral analysis.

| Capability | Epic | Backend | Inputs | Outputs |
|---|---|---|---|---|
| Integration registry | V9.1 | Cuba + FFTW | — | Cuba/FFTW handles mapped to Yamori identifiers |
| Monte Carlo integration | V9.2 | Cuba (Vegas/Suave) | Integrand, bounds, dimensions, seed | Integral estimate, statistical error, convergence |
| Deterministic integration | V9.3 | Cuba (Divonne/Cuhre) | Smooth integrand, bounds, tolerance | Integral estimate, deterministic error bound |
| FFT spectral analysis | V9.4 | FFTW | Input series, transform direction | Transformed series, spectral density, cycle periods |
| Spectral filtering | V9.5 | FFTW | Transformed series, filter parameters | Filtered series, identified cycle periods |

---

## Supported Input Types

| Input | Format | Source | Notes |
|---|---|---|---|
| Financial statements | XBRL filings, CSV | SEC EDGAR, Damodaran datasets | US-GAAP and IFRS elements mapped to canonical names |
| Market data | CSV, Arrow C Data Interface | Market data providers | OHLCV, volume, corporate actions |
| Policy inputs | JSON, Yamori types | User-supplied, validated | Risk-free rate, tax rate, growth assumptions |
| Dataset manifest | YAML/JSON with SHA-256 hashes | Build-time, versioned | Per-file hash, vintage, source URL, row count |
| Company metadata | JSON (canonical IDs) | User-supplied or catalog | ISIN/CUSIP, MIC, ISO 4217 currency, sector assignment |
| Peer-set definitions | JSON (persisted) | User-supplied | Not re-guessed per run; sourced input with versioning |

---

## Supported Output Types

| Output | Format | Description |
|---|---|---|
| Intrinsic value per share | Yamori `Money<C>` type | With provenance chain, audit trail, and provenance hash |
| Monte Carlo distribution | Yamori result with percentiles | Mean, median, P5/P25/P50/P75/P95, valuation range |
| Sensitivity matrix | Yamori table type | WACC × growth grid of intrinsic values |
| Reverse DCF result | Yamori `Rate` type | Implied growth rate with market interpretation |
| Technical indicators | Yamori Series type | Deterministic, bit-identical across platforms |
| Option prices & Greeks | Yamori types | Per-instrument, full Greek vector |
| Portfolio optimization | Yamori types | Weights, expected return, risk, Sharpe, constraint status |
| Spectral analysis | Yamori Series type | Frequency-domain transforms, cycle detection |
| Valuation reports | JSON + structured narrative | Executive summary, methodology, full provenance |
| Audit trail | BLAKE3 provenance hash | `BLAKE3(canonical(inputs) ‖ policy ‖ semver ‖ dataset manifest)` |

---

## Cross-Domain Composition

All domains share the same runtime. A single Yamori representation can flow through multiple domains:

```text
CSV / Arrow data
       │
       ▼
financial series
       │
       ├── M2: ratios, valuation, FCFF
       ├── M3: adjustments, normalization
       ├── M4: reverse DCF, Monte Carlo, sensitivity
       ├── M6: technical indicators (price series)
       ├── M7: options pricing (vol, rate, underlying)
       ├── M8: factor models, risk (returns series)
       └── M9: spectral analysis (cycle detection)
```

The dependency graph built in M1 serves all domains. Each domain registers its operations as named nodes. The same backend router, shared-memory representation, C ABI, and deterministic execution policy apply uniformly.

---

## Backend Libraries

| Library | Domain | Purpose | Introduced |
|---|---|---|---|
| **Apache Arrow C++** | All | Canonical memory representation, CSV I/O, compute registry, cross-language interchange | M1 |
| **GNU GSL** | Valuation | Statistics (medians, outlier filtering), interpolation (transition paths), roots (reverse DCF), RNG (Monte Carlo) | M2 |
| **TA-Lib** | Technical Analysis | Moving averages, oscillators, volatility, trend, volume indicators, candlestick patterns | M6 |
| **QuantLib** | Options & Derivatives | Options pricing, fixed income, yield curves, volatility surfaces | M7 |
| **BLAS + LAPACK** | Portfolio Analytics | Vector/matrix operations, eigenvalue decomposition, SVD, Cholesky, linear solvers | M8 |
| **Cuba** | Advanced Analytics | Multidimensional Monte Carlo (Vegas, Suave) and deterministic integration (Divonne, Cuhre) | M9 |
| **FFTW** | Advanced Analytics | Fast Fourier transforms, spectral analysis, signal filtering, cycle detection | M9 |

A new library enters Yamori only when a domain requires capabilities the current backends do not provide — not because the library happens to be useful.

---

## Non-Capabilities

Yamori does not provide:

- Algorithm implementations. Yamori owns the contract; the backends own the algorithms.
- Interactive research notebooks. Python is an important frontend, but Yamori does not embed Python as its architecture.
- Real-time market data feeds. Yamori processes data that is supplied to it.
- Trading execution or order management.
- Machine learning or neural network inference.
- Natural language processing or sentiment analysis.
- Portfolio management or position tracking (beyond analytics on portfolio inputs).
- Any capability that leaks backend types through Yamori's public surface.

---

## The Moat

Yamori's defensibility is not function count. It is structural:

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

If Yamori becomes merely a collection of wrappers, there is little reason for it to exist. If it becomes the standard data plane and execution contract through which heterogeneous quantitative engines compose, it solves a substantially harder problem.

---

## Cross-References

- Product bet, target user, and priority stack: [`positioning.md`](positioning.md).
- Methodology decisions: [`doc/knowledge/architecture.md`](../../../knowledge/architecture.md).
- Coding conventions: [`execution/contribution/yamori.md`](../../../execution/contribution/yamori.md).
- Milestone details: [`roadmap/milestones/README.md`](roadmap/milestones/README.md).
- Epic breakdown: [`roadmap/epics/README.md`](roadmap/epics/README.md).
