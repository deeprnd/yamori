# Yamori Strategy

## Purpose

This directory owns Yamori product strategy: what the product is, who it is
for, how the roadmap is organized, and where product decisions should be made.
Architecture, valuation methodology, and implementation details remain in the
knowledge and execution docs.

## What Yamori Is

Yamori is a native quantitative-computing runtime that unifies mature specialized
libraries behind one stable C ABI and one shared data model.

It performs Damodaran-style FCFF discounted cash flow valuations as its first
and deepest domain, then generalizes to technical analysis, portfolio analytics,
derivatives pricing, and multidimensional integration — all over the same
dependency graph, backend router, and shared-memory representation.

Yamori:

- Provides one coherent API (`yamori.array`, `yamori.linalg`, `yamori.timeseries`,
  `yamori.ta`, `yamori.optimize`, `yamori.integrate`, `yamori.options`,
  `yamori.curves`, `yamori.risk`) that describes problems, not implementations.
- Exposes a stable C ABI — Python, Zig, Rust, C++, Go, Java, C# — all connect
  to the same runtime.
- Shares one memory model (`Buffer` → `Array` → `Series` → `Table`) so that
  backend adaptation is primarily a matter of constructing views rather than
  copying datasets.
- Routes every operation through a capability registry to the appropriate backend
  engine.
- Produces deterministic, reproducible results with a provenance hash — bit-identical
  across Linux x86, Linux ARM, macOS ARM, and Windows x86.
- Does not implement algorithms itself. Yamori owns the contract; the backends own
  the algorithms.

The core rule is:

> **Own the contract. Delegate the implementation.** Yamori owns the API, ABI,
> types, memory model, ownership semantics, routing, execution policy, errors,
> versioning, testing, and distribution. Backends own the algorithms.

## What Yamori Is Not

Yamori is not:

- another NumPy implementation
- another SciPy
- another pandas
- another Polars
- another PyMC
- another QuantLib
- a wrapper collection — wrappers are trivially copied; the moat is data
  representation, routing, and determinism
- a trading recommendation engine
- a portfolio manager or robo-advisor
- a real-time quote or market data platform
- a technical analysis retail tool
- a sentiment or news analysis engine
- a generic financial calculator

Yamori is built for developers and organizations that need to compose multiple
best-in-class quantitative engines (Arrow, GSL, TA-Lib, QuantLib, BLAS/LAPACK,
Cuba, FFTW) behind one language-neutral runtime — not for users who need a single
Python package for a single domain.

## Positioning

One-line positioning:

> **Yamori is a native quantitative-computing runtime that unifies mature specialized
> libraries behind one stable ABI and one shared data model.**

A more explanatory version:

> Yamori provides one coherent native API over best-in-class numerical, statistical,
> time-series, and financial libraries — without embedding Python or tying deployment
> to a language-specific ecosystem.

And the strategic aspiration:

> **The only quantitative runtime your application should need to integrate.**

The financial-computing ecosystem has excellent libraries. The problem is that they
exist as separate islands, each with its own API, types, memory model, ownership
rules, error handling, threading model, build system, versioning, and language
bindings. A sophisticated application therefore ends up building its own integration
layer — and many organizations independently recreate some version of that
infrastructure.

Yamori exists to build that layer once.

Applications should not need to individually integrate Apache Arrow, GNU GSL,
TA-Lib, QuantLib, BLAS/LAPACK, Cuba, FFTW, and other specialized engines. They
integrate Yamori once.

## Runtime Thesis

Yamori is built as a **native quantitative runtime**, not as a Python library
wrapping native code.

The product sequence is:

```text
runtime first
domains second
integration third
frontends last
```

The runtime must deliver durable infrastructure before any domain milestone:

```text
named formula dependency graph
    → unified backend router
    → shared-memory representation
    → C ABI
    → deterministic execution policy
    → valuation, TA, portfolio, derivatives, advanced analytics
```

The deterministic execution policy is foundational — it pins algorithms, pins RNG
with explicit seed, enforces deterministic threading, disables fast-math, and uses
iterated multiplication for discount factors. Without it, no downstream domain can
claim reproducibility.

A new library enters Yamori only when a domain requires capabilities the current
backends do not provide — not because the library happens to be useful.

## Core Principles

1. **Own semantics. Delegate implementation.** Yamori owns the contract; backends
   own the algorithms. Exceptions require concrete justification — no suitable
   upstream, critical interoperability requirement, significant performance advantage,
   or backend-independent primitive needed.

2. **Composition before coverage.** The objective is not to support 10,000
   functions. It is to make 100 important functions from ten different domains
   compose correctly over one representation. Market prices → returns → rolling
   volatility → model calibration → option valuation → scenario risk — all stages
   operating over Yamori objects without backend-specific conversion code.

3. **Avoid backend leakage.** Yamori functions accept and return Yamori types,
   never backend types. `yamori.ta.macd()` returns a Yamori Series, not a GSL
   vector. Backend representations remain private.

4. **Native first, Python excellent.** Python is an important frontend with
   ergonomic bindings, but the runtime does not embed or depend on Python. Python
   is the ergonomic interface, not the architectural owner.

5. **Deterministic execution.** Produces bit-identical results across all four
   supported platforms. Every result carries a provenance hash. Golden tests assert
   on the hash rather than on individual figures.

6. **Shared memory from the start.** Zero-copy data sharing is not an afterthought
   — it is the design target. Cross-process data exchange uses workspace IDs, buffer
   offsets, and byte lengths rather than process-local pointers.

## Source Of Truth

| Document | Owns | Does not own |
| --- | --- | --- |
| [`README.md`](README.md) | Product identity, strategy directory guide, what Yamori is | Valuation methodology, implementation tasks |
| [`positioning.md`](positioning.md) | Market position, differentiation, buyer framing | Delivery sequencing or implementation tasks |
| [`roadmap/`](roadmap/) | Versioned milestones, story files, evidence gates, increment status | Market narrative or methodology decisions |
| [`templates/`](templates/) | GitHub issue templates for epics, stories, tasks, proposals, and status | Valuation methodology source of truth |
| [`capabilities.md`](capabilities.md) | Runtime capabilities, domain capabilities, input/output types, backend libraries | Implementation-specific tile APIs |
| [`doc/knowledge/architecture.md`](../knowledge/architecture.md) | System layers, data flow, source-of-truth boundaries, domain architecture, runtime foundation | Product backlog sequencing |
| [`doc/execution/observability.md`](../execution/observability.md) | Observability surface, audit signals, failure transparency, alerting policy | Runtime foundation or capability definitions |
| [`doc/execution/telemetry.md`](../execution/telemetry.md) | Telemetry semantics and metrics conventions | Valuation methodology |

## Product Operating Model

### Planning Cadence

- Roadmap review: update when product priority, version order, or strategic
  scope changes.
- Story grooming: update when stories split, merge, or change acceptance
  criteria.
- Capability review: update when a domain capability, backend routing, or shared
  memory representation changes.
- Methodology review: update when Damodaran framework changes or new accounting
  adjustments are adopted.
- Architecture review: update when runtime foundation (dependency graph, backend
  router, C ABI, deterministic execution policy) changes.

### Decision Rules

1. If the question is "what is Yamori and why does it exist?", update this
   README.
2. If the question is "how is Yamori positioned in the market?", update
   `positioning.md`.
3. If the question is "when does this happen?", update the relevant roadmap
   story under `roadmap/`.
4. If the question is "what exact work remains?", update the relevant roadmap
   story under `roadmap/`.
5. If the question is "what valuation methodology should be used?", update
   `doc/knowledge/architecture.md` or the relevant methodology doc.
6. If the question is "which runtime capability or backend is affected?", update
   `capabilities.md`.

## Senior Product Constraints

- Keep M1 (runtime foundation) as the true first milestone — no domain milestone
  ships without the dependency graph, backend router, shared-memory representation,
  C ABI, and deterministic execution policy.
- Do not implement algorithms that mature backends already cover. If Arrow, GSL,
  TA-Lib, QuantLib, BLAS/LAPACK, Cuba, or FFTW provide it, route to them.
- Never let backend types leak through Yamori's public surface.
- Never mix the translate-at-the-end and translate-the-flows currency methods.
  The single most common form of this error is discounting reporting-currency
  cash flows at a reader-currency WACC.
- Deterministic execution is non-negotiable. If a numerical path reaches a reported
  number, it must produce the same result on every platform.
- Shared-memory representation uses offset-based descriptors — never process-local
  pointers — from the first milestone.
- Python is a frontend, not the architecture. Yamori must deploy as a native
  binary dependency without requiring Python.
- A new library enters Yamori only when a domain requires capabilities the current
  backends do not provide.

## Current V1 Narrative

V1 proves that Yamori can serve as a composable quantitative runtime with a
working Damodaran valuation engine at its core:

1. The runtime foundation (M1) delivers a working dependency graph, backend router,
   shared-memory representation, C ABI, and deterministic execution policy.
2. The Damodaran valuation engine (M2) produces FCFF-based DCF valuations with
   WACC, three-stage growth, terminal value, and per-share intrinsic value — all
   from adjusted financial statements and policy inputs.
3. Financial statement ingestion (M3) normalizes XBRL filings with R&D capitalization,
   lease capitalization, SBC deduction, base-year normalization, and TTM resolution.
4. Cross-checks and uncertainty (M4) add reverse DCF, relative multiples, sensitivity
   matrices, scenario analysis, audit checks, and Monte Carlo simulation.
5. Comparative analysis and reports (M5) extend single-company valuation to peer-set
   batch valuation, structured reports, historical replay, and deterministic audit
   trails.

Subsequent milestones (M6–M9) generalize the runtime beyond valuation into
technical analysis, options and derivatives, portfolio analytics, and advanced
analytics — each registering as named nodes on the same dependency graph, routed
through the same backend router, over the same shared-memory representation.

## Users

Yamori is built for developers and organizations working in quantitative finance
and computational economics:

- quantitative research teams
- systematic trading firms
- asset managers and portfolio analytics teams
- derivatives pricing desks
- risk management teams
- financial data platform builders
- API designers building quantitative infrastructure
- organizations that need the same numerical runtime from multiple languages
- teams that need deterministic, reproducible financial computation
- developers who need to compose multiple best-in-class libraries without
  maintaining per-library bindings

## Strategic Differentiation

Most numerical libraries optimize for **function count**. Yamori optimizes for
**composability**.

The differentiation is the combination of:

```text
one API
+ one ABI
+ one memory model
+ backend routing
+ shared-memory architecture
+ deterministic execution policy
```

Generic scientific stacks show what a single library can do. Yamori shows how
multiple best-in-class engines compose correctly over one representation — market
data flowing through technical indicators, portfolio analytics, and pricing engines
without backend-specific conversion code.

The prototype-to-production advantage is structural: Python research and native
production can call the same numerical implementation with the same parameters,
seeds, and data representation. That is a meaningful architectural advantage for
quantitative systems where reproducibility matters.

## Status

The current repository contains Yamori's Damodaran-style DCF valuation engine
foundation under `src/app/yamori/` and `src/yamori/`. The active implementation
is the Zig-native runtime with the M1 foundation and M2 valuation engine.

The intended V1 is a narrow, opinionated implementation focused on:

- runtime foundation: dependency graph, backend router, shared-memory, C ABI,
  deterministic execution policy
- Damodaran FCFF valuation: WACC, three-stage growth, terminal value, per-share
  intrinsic value
- financial statement normalization: XBRL mapping, R&D and lease capitalization,
  SBC deduction, base-year normalization
- cross-checks: reverse DCF, sensitivity matrices, scenario analysis
- deterministic audit trail: provenance hash, golden tests, failure transparency
