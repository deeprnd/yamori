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

These are domain-independent capabilities that every financial domain builds on.

| Capability | Description |
|---|---|
| **Financial formula dependency graph** | Named formulas as nodes over source metrics. Derived metrics resolve in deterministic topological order without performing numerical work themselves. Enables sensitivity analysis, Monte Carlo simulation, and reverse DCF because evaluation traverses the graph rather than calling a monolithic function. |
| **Unified backend router** | Every direct library invocation flows through one stable semantic dispatch layer. Registers Arrow compute functions, GSL adapters, and external library backends behind a capability registry that maps each Yamori operation to its backend implementation. Normalizes backend failures into Yamori statuses and prevents backend types from leaking through Yamori's public surface. |
| **Shared-memory representation** | Same financial arrays and tables mapped by multiple processes with Arrow-compatible layout. Uses offset-based buffer descriptors (workspace ID + buffer offset + byte length) rather than process-local pointers. Enables zero-copy process attach for cross-process data sharing. |
| **C ABI** | Language-neutral interface exposing all runtime capabilities through C-callable functions. Uses Arrow C Data Interface structures for array/table interchange. Provides opaque handles for backend state. ABI compatibility tests detect accidental binary-interface breakage across releases. |
| **Deterministic execution policy** | Pins algorithms, pins RNG with explicit seed, enforces deterministic threading policy, specifies reduction order, disables fast-math. Produces bit-identical results across Linux x86, Linux ARM, macOS ARM, and Windows x86. |

---

## Valuation Capabilities (Damodaran)

The first and primary financial domain. Every capability traverses the same dependency graph.

### Damodaran Valuation Engine

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| Core valuation runner | Arrow + GSL | Adjusted financial statements, policy inputs | `runValuation()` graph traversal |
| Historical metrics & ROIC | Arrow + GSL | Revenue, EBIT, balance-sheet series | NOPAT, invested capital, ROIC, reinvestment rate, outlier-filtered sustainable inputs |
| Cost of capital & WACC | Arrow + GSL | Sector unlevered beta, D/E, geographic revenue split, synthetic rating | Bottom-up beta, revenue-weighted CRP, cost of equity, cost of debt, WACC |
| Three-stage growth & FCFF projection | Arrow + GSL | Sustainable ROIC, sustainable reinvestment rate | High-growth rate, transition paths (10-year), FCFF schedule |
| Terminal value & per-share value | Arrow + GSL | FCFF schedule, WACC, terminal growth rate, debt/cash/non-operating assets | Intrinsic value per share, terminal value share |

### Financial Statement Ingestion

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| XBRL mapping | Arrow (CSV) | XBRL filings (US-GAAP, IFRS) | Normalized typed internal representation with provenance |
| R&D capitalization | Arrow + GSL | EBIT, R&D expense, sector | Amortizing R&D asset, adjusted EBIT, adjusted invested capital |
| Lease capitalization | Arrow + GSL | Operating lease obligations, discount rate | Capitalized lease obligations, adjusted EBIT, adjusted debt |
| SBC deduction | Arrow + GSL | Stock-based compensation, outstanding options | SBC as operating expense, diluted share count, option fair value |
| Base-year normalization | Arrow + GSL | Five-year historical margins, current period | Normalized EBIT, distortion detection report |
| TTM & source priority | Arrow + GSL | Fiscal-year data, multiple filing sources | Trailing-twelve-month metrics, resolved source citation |

### Cross-Checks, Sensitivity, and Monte Carlo

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| Reverse DCF | GSL (Roots) | Market price, all other DCF assumptions fixed | Implied Stage 1 growth rate |
| Relative-multiple cross-checks | Arrow | Intrinsic equity value, EBITDA, shares | Implied P/E, P/S, EV/EBITDA, exit-multiple terminal value |
| Sensitivity matrices | Arrow + GSL | WACC range, growth range grid | Intrinsic value matrix (deterministic, reproducible) |
| Scenario analysis | Arrow | Bull/base/bear/stress input sets | Scenario distribution with base-case preservation |
| Audit checks | Arrow | All valuation outputs | Severity-flagged assertions (Error/Warn/Info) |
| Random sampling | GSL (RNG) | Seed, distribution specs, hard constraints | Reproducible samples for growth, margin, WACC, ROIC |
| Monte Carlo runner | Arrow + GSL | N sampled input sets, `runValuation()` | N intrinsic values with invalid-sample handling |
| Monte Carlo summary | GSL (Statistics) | N intrinsic values | Mean, stddev, median, P5/P25/P50/P75/P95, valuation range |

### Comparative Analysis & Reports

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| Peer-set management | Arrow | Company identifiers, sector assignments | Managed peer sets, canonical identifiers, consistent sector assignments |
| Batch valuation | Arrow | Peer set, shared policy objects | Per-company valuation table with valuation, statement, and cross-check outputs |
| Valuation reports | Arrow | Valuation, statement, and cross-check outputs, methodology assumptions | Structured JSON + narrative report with full provenance |
| Historical replay | Arrow | Historical financial data, past dates | Historical intrinsic values, bit-identical reproducibility |
| Audit trail | Arrow | Dataset manifest, policy, adjustments | BLAKE3 provenance hash, deterministic audit chain |
| Dataset versioning | Arrow | Dataset files | SHA-256 manifest, version tracking, refresh detection |
| CLI interface | — | JSON input, dataset manifest | JSON output, MCP server contract |
| Relative valuation metrics | Arrow | Peer-set valuations | Discount/premium to peer median, percentile ranks |
| Sector-relative positioning | Arrow | Peer-set results, sector benchmarks | WACC/ROIC/growth vs. sector medians, deviation flags |

---

## Technical Analysis Capabilities

First domain proving the runtime generalizes beyond valuation.

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| Indicator registry | TA-Lib | — | TA-Lib function handles mapped to Yamori identifiers |
| Moving averages | TA-Lib | Price series, period | SMA, EMA, WMA, DEMA, TEMA, KAMA, MAMA, T3 |
| Oscillators | TA-Lib | Price series, period | RSI, Stochastic, CCI, ROC, MOM |
| Volatility & trend | TA-Lib | OHLCV series | Bollinger Bands, ATR, ADX, Parabolic SAR |
| Volume & patterns | TA-Lib | OHLCV series | OBV, AD, ADOSC, candlestick pattern signals |

---

## Options & Derivatives Capabilities

Handles closed-form and numerically-intensive pricing.

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| Pricing registry | QuantLib | — | QuantLib pricing engines mapped to Yamori identifiers |
| Equity options | QuantLib | Underlying, strike, maturity, vol, dividend, rate | Fair value, Delta/Gamma/Vega/Theta/Rho (closed-form + tree) |
| Exotic options | QuantLib | Same + barriers, averages, lookback | Monte Carlo/finite-difference pricing with Greeks |
| Fixed income | QuantLib | Cash flows, yield curve, day-count | Bond prices, swap NPV, caps/floors, yield curve |
| Vol surfaces & curves | QuantLib | Market quotes, fitting method | Implied vol surfaces, bootstrapped yield curves |

---

## Portfolio Analytics Capabilities

Matrix-heavy computation where shared memory becomes operationally essential.

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| Linear algebra registry | BLAS/LAPACK | — | BLAS/LAPACK handles mapped to Yamori identifiers |
| Covariance estimation | BLAS | Return series | Sample/rolling/ewma covariance, Ledoit-Wolf shrinkage |
| Factor models | BLAS + LAPACK | Return series, factor definitions | PCA components, factor loadings, residuals |
| Risk decomposition | LAPACK | Covariance, portfolio weights | Factor/asset/marginal contributions, component VaR |
| Portfolio optimization | LAPACK | Expected returns, covariance, constraints | Optimized weights, Sharpe, constraint status |
| Portfolio simulation | BLAS + GSL | Weights, scenarios, RNG seed | Portfolio value distributions, drawdown analysis |

---

## Advanced Analytics Capabilities

High-dimensional integration and spectral analysis.

| Capability | Backend | Inputs | Outputs |
|---|---|---|---|
| Integration registry | Cuba + FFTW | — | Cuba/FFTW handles mapped to Yamori identifiers |
| Monte Carlo integration | Cuba (Vegas/Suave) | Integrand, bounds, dimensions, seed | Integral estimate, statistical error, convergence |
| Deterministic integration | Cuba (Divonne/Cuhre) | Smooth integrand, bounds, tolerance | Integral estimate, deterministic error bound |
| FFT spectral analysis | FFTW | Input series, transform direction | Transformed series, spectral density, cycle periods |
| Spectral filtering | FFTW | Transformed series, filter parameters | Filtered series, identified cycle periods |

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
       ├── valuation & statement: ratios, valuation, FCFF, adjustments
       ├── cross-checks: reverse DCF, Monte Carlo, sensitivity
       ├── technical indicators (price series)
       ├── options pricing (vol, rate, underlying)
       ├── factor models, risk (returns series)
       └── advanced analytics: multidimensional integration, spectral analysis
```

The dependency graph serves all domains. Each domain registers its operations as named nodes. The same backend router, shared-memory representation, C ABI, and deterministic execution policy apply uniformly.

---

## Backend Libraries

| Library | Domain | Purpose |
|---|---|---|
| **Apache Arrow C++** | All | Canonical memory representation, CSV I/O, compute registry, cross-language interchange |
| **GNU GSL** | Valuation | Statistics (medians, outlier filtering), interpolation (transition paths), roots (reverse DCF), RNG (Monte Carlo) |
| **TA-Lib** | Technical Analysis | Moving averages, oscillators, volatility, trend, volume indicators, candlestick patterns |
| **QuantLib** | Options & Derivatives | Options pricing, fixed income, yield curves, volatility surfaces |
| **BLAS + LAPACK** | Portfolio Analytics | Vector/matrix operations, eigenvalue decomposition, SVD, Cholesky, linear solvers |
| **Cuba** | Advanced Analytics | Multidimensional Monte Carlo (Vegas, Suave) and deterministic integration (Divonne, Cuhre) |
| **FFTW** | Advanced Analytics | Fast Fourier transforms, spectral analysis, signal filtering, cycle detection |

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

Post-M4 additions (not part of the initial Damodaran scope): QuantLib (options/derivatives), Cuba (multidimensional integration), BLAS/LAPACK (portfolio analytics), TA-Lib (technical analysis), and FFTW (spectral analysis) are each introduced only when a domain requires capabilities the current backends do not provide. They are not part of M1–M4.

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
