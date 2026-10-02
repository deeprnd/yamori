# Roadmap — Yamori Intrinsic Valuation Engine (Tickoni Pillar)

Use this folder for per-increment planning, tracking, and reference. GitHub is
the issue tracker: epics, stories, and tasks are all GitHub issues with
different labels and sub-issue relationships.

**Tickoni pillar**: Every epic in this roadmap is designed to strongly support
the Tickoni project. Valuation outputs feed downstream Tickoni tiles; the
`runValuation()` pipeline is the canonical callable pivot; audit trails, provenance
hashes, and dataset manifests are consumed by Tickoni's research and comparison
systems.

## Issue Hierarchy

| Type | GitHub label | Purpose | Relationship |
| --- | --- | --- | --- |
| Epic | `type/epic` | Huge new feature or product increment. Groups related stories that deliver a complete capability across domains. | Has story sub-issues |
| Story | `story` | Single implementable deliverable that can be independently verified. | Sub-issue of one epic, has task sub-issues |
| Task | `task` | Domain-scoped implementation work for one story. | Sub-issue of one story |

Use these templates:

- [`epic-template.md`](../../templates/epic-template.md)
- [`story-template.md`](../../templates/story-template.md)
- [`status-template.md`](../../templates/status-template.md)

Use these project docs to fill and implement issues:

- [`README.md`](../../README.md) for product identity, supported workflows, and
  non-goals.
- [`architecture.md`](../../../knowledge/architecture.md) for valuation method,
  data flow, and output structure.
- [`contrib/yamori.md`](../../../execution/contribution/yamori.md) for Yamori
  coding style and implementation conventions.
- [`build-system.md`](../../../build-system.md) and [`development.md`](../../../execution/development.md)
  for repo-facing build/run commands.
- [`testing-yamori.md`](../../../execution/testing-yamori.md) and
  [`ci.md`](../../../execution/ci.md) for local verification and CI expectations.
- [`security.md`](../../../execution/security.md) for data handling and input
  validation requirements.
- [`observability.md`](../../../execution/observability.md) and
  [`telemetry.md`](../../../execution/telemetry.md) for metrics, diagnostics, and
  operator-visible evidence.

## Epics By Milestone

### Milestone 1: Yamori Runtime Foundation

| Epic | Description |
| --- | --- |
| [V1.1](V1.1.md) | Financial formula dependency graph — named nodes, topological resolution, sensitivity/MC/reverse DCF |
| [V1.2](V1.2.md) | Unified backend router — Arrow/GSL dispatch, capability registry, error translation, type isolation |
| [V1.3](V1.3.md) | Shared-memory representation — Arrow C Data Interface, offset-based buffers, zero-copy process attach |
| [V1.4](V1.4.md) | C ABI — Arrow C structures, Yamori status/function ABI, opaque handles, ABI compatibility tests |
| [V1.5](V1.5.md) | Deterministic execution policy — pinned algorithms, RNG, threading, reduction order, fast-math disabled |

### Milestone 2: Damodaran Valuation Engine

| Epic | Description |
| --- | --- |
| [V2.1](V2.1.md) | Core types, policy, and valuation runner — `Money`, `Rate`, `Period`, `runValuation()` graph traversal |
| [V2.2](V2.2.md) | Historical metrics and ROIC — NOPAT, invested capital, ROIC, outlier filtering, sustainable inputs |
| [V2.3](V2.3.md) | Cost of capital and WACC — bottom-up beta, CRP, cost of equity, cost of debt, capital weights |
| [V2.4](V2.4.md) | Three-stage growth model and FCFF projection — high-growth rate, transition paths, 10-year FCFF |
| [V2.5](V2.5.md) | Terminal value, equity bridge, and per-share value — discount factors, Gordon terminal value, FX translation |

### Milestone 3: Financial Statement Ingestion

| Epic | Description |
| --- | --- |
| [V3.6](V3.6.md) | Financial statement ingestion and XBRL mapping — US-GAAP/IFRS normalization, provenance, source document |
| [V3.7](V3.7.md) | R&D capitalization adjustment — amortizing asset, EBIT/invested capital adjustments |
| [V3.8](V3.8.md) | Lease capitalization adjustment — capitalized lease obligations, EBIT/invested capital consistency |
| [V3.9](V3.9.md) | Stock-based compensation and diluted shares — SBC deduction, option dilution, Black-Scholes/treasury fallback |
| [V3.10](V3.10.md) | Base-year normalization and distortion detection — 5-year median margin, 30% distortion test, provenance |
| [V3.11](V3.11.md) | TTM calculation and source-priority resolution — 10-K > 10-Q > earnings release > consensus |

### Milestone 4: Cross-Checks and Monte Carlo

| Epic | Description |
| --- | --- |
| [V4.12](V4.12.md) | Reverse DCF — GSL bisection solver, 100 iterations, implied growth rate |
| [V4.13](V4.13.md) | Relative-multiple cross-checks — implied P/E, P/S, EV/EBITDA, exit-multiple terminal value |
| [V4.14](V4.14.md) | Sensitivity matrices — WACC/growth grid, deterministic graph traversal per cell |
| [V4.15](V4.15.md) | Scenario analysis — bull/base/bear/stress, base-case preservation |
| [V4.16](V4.16.md) | Audit checks and severity enforcement — 10 assertions with Error/Warn/Info severity levels |
| [V4.17](V4.17.md) | Random sampling — GSL RNG, seeded streams, Gaussian/log-normal/uniform distributions |
| [V4.18](V4.18.md) | Monte Carlo valuation runner — N sampled sets through `runValuation()`, invalid sample handling |
| [V4.19](V4.19.md) | Monte Carlo summary — mean, dispersion, percentiles, valuation range, reproducibility test |
| [V4.20](V4.20.md) | Monte Carlo demo — base-case preservation, distribution output |

### Milestone 5: Comparative Analysis and Reports

| Epic | Description |
| --- | --- |
| [V5.21](V5.21.md) | Peer-set management and company catalog — canonical identifiers, sector assignments |
| [V5.22](V5.22.md) | Batch valuation runner — M2 `runValuation()` across peer set, shared policy objects |
| [V5.23](V5.23.md) | Valuation report generation — structured JSON report with executive summary, methodology, WACC, growth, FCFF, cross-checks, Monte Carlo, audit |
| [V5.24](V5.24.md) | Historical replay and backtesting — past-date valuations, bit-identical reproducibility |
| [V5.25](V5.25.md) | Deterministic audit trail and provenance hash — BLAKE3 hash, golden test assertions |
| [V5.26](V5.26.md) | Dataset versioning and manifest management — SHA-256 hashes, vintages, refresh detection |
| [V5.27](V5.27.md) | CLI and export interfaces — JSON input/output, MCP server contract |
| [V5.28](V5.28.md) | Relative valuation metrics — discount/premium to peer median, percentile ranks, edge cases |
| [V5.29](V5.29.md) | Sector-relative positioning — WACC/ROIC/growth vs. sector medians, deviation flags |

### Milestone 6: Technical Analysis

| Epic | Description |
| --- | --- |
| [V6.1](V6.1.md) | TA-Lib integration and indicator registry — TA-Lib backend, parameter resolution, graph registration |
| [V6.2](V6.2.md) | Moving average indicators — SMA, EMA, WMA, DEMA, TEMA, KAMA, MAMA, T3 |
| [V6.3](V6.3.md) | Oscillator indicators — RSI, Stochastic, CCI, ROC, MOM |
| [V6.4](V6.4.md) | Volatility and trend indicators — Bollinger Bands, ATR, ADX, Parabolic SAR |
| [V6.5](V6.5.md) | Volume indicators and pattern recognition — OBV, AD, ADOSC, candlestick patterns |
| [V6.6](V6.6.md) | Technical analysis demo — complete workflow, cross-domain composition, deterministic reproducibility |

### Milestone 7: Options and Derivatives

| Epic | Description |
| --- | --- |
| [V7.1](V7.1.md) | QuantLib integration and pricing registry — QuantLib backend, instrument requirements, graph registration |
| [V7.2](V7.2.md) | Equity option pricing — European (Black-Scholes-Merton), American (CRR/Bjerksund-Stensland), Greeks |
| [V7.3](V7.3.md) | Exotic option pricing — barrier, Asian, lookback, compound; Monte Carlo/finite-difference engines |
| [V7.4](V7.4.md) | Fixed income instruments — bonds, swaps, caps, floors, yield curve construction |
| [V7.5](V7.5.md) | Volatility surface and yield curve management — implied vol fitting, interpolation, shared-memory storage |
| [V7.6](V7.6.md) | Derivatives demo — complete workflow, cross-domain composition, deterministic reproducibility |

### Milestone 8: Portfolio Analytics

| Epic | Description |
| --- | --- |
| [V8.1](V8.1.md) | BLAS/LAPACK integration and linear algebra registry — BLAS/LAPACK backend, operation requirements, graph registration |
| [V8.2](V8.2.md) | Covariance estimation and correlation analysis — sample/rolling/ewma covariance, Ledoit-Wolf shrinkage |
| [V8.3](V8.3.md) | Factor models — PCA via SVD, factor extraction, factor regression, user-defined and data-driven factors |
| [V8.4](V8.4.md) | Risk decomposition — factor/asset/marginal contributions, component VaR, expected shortfall, risk parity |
| [V8.5](V8.5.md) | Portfolio optimization — Markowitz, minimum variance, max Sharpe, risk parity, Black-Litterman, constraints |
| [V8.6](V8.6.md) | Portfolio simulation and scenario analysis — historical/Monte Carlo scenarios, drawdown analysis, tail risk |
| [V8.7](V8.7.md) | Historical scenario analysis and backtesting — rolling optimization, weight drift, turnover, rebalance frequency |

### Milestone 9: Advanced Analytics

| Epic | Description |
| --- | --- |
| [V9.1](V9.1.md) | Cuba/FFTW integration and registry — Vegas/Suave/Cuhre/Divonne, FFT/DCT/DST, graph registration |
| [V9.2](V9.2.md) | Monte Carlo integration and portfolio simulation — Vegas/Suave, variance reduction, deterministic seeding |
| [V9.3](V9.3.md) | Deterministic integration for pricing and calibration — Cuhre/Divonne, high-precision, error bounds |
| [V9.4](V9.4.md) | FFT spectral analysis — real/complex DFT, DCT, DST, plan strategy, signal decomposition |
| [V9.5](V9.5.md) | Spectral filtering and cycle decomposition — bandpass/low-pass filtering, cycle detection, peak significance |
| [V9.6](V9.6.md) | Advanced analytics demo — complete workflow, five-domain composition, deterministic reproducibility |

## How Roadmap Files Are Organized

Roadmap files capture product sequencing and acceptance context. They may link
to the GitHub epic/story/task issues that own active execution.

**Roadmap section** — product intent, user story, what the user can do, what the
user sees, capability depth, success demo, non-goals.

**Breakdown section** — story issues (S1, S2, ...), each with task sub-issues
and acceptance criteria. Split by domain only where it helps deliver a
self-contained, testable story.

## Status Legend

For full epic, story, and task issue statuses, use
[`status-template.md`](../../templates/status-template.md).

All issue types use the same status enum:

`Backlog | Refining | Ready | In Progress | Review | Verification | User Accepted | Done | Blocked`

## Cross-References

- Product bet, target user, and priority stack: [`positioning.md`](../../positioning.md).
- Methodology decisions: [`doc/knowledge/architecture.md`](../../../knowledge/architecture.md).
- Coding conventions: [`execution/contribution/yamori.md`](../../../execution/contribution/yamori.md).

## Increment Gate Checklist

Every increment must answer before closing:

- What can the user do now that they could not before this increment?
- What changed from the previous increment?
- What is the demo moment (command or flow that proves the increment)?
- Which inputs, assumptions, and data sources are required?
- What happens when data is missing, stale, or inconsistent?
- Is the output reproducible with the same inputs?
- Which fixtures, sample data, and verification cases prove the behavior?
- Are methodology decisions documented in the knowledge base?
- Can the valuation be replayed from the same inputs and produce the same output?
- What intentional divergence or blocked-flow example proves error handling?

## Evidence Work Items

Every story should include child task issues for evidence and quality gates.
Use conditional evidence: require methodology, data, output, or testing proof
only when the story touches that boundary. Mark an item `N/A - reason` when
reviewers may otherwise expect it.
