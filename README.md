# Yamori 🏯

**One Coherent Native Quantitative-Computing Runtime Over Best-in-Class Libraries.**

<p align="center">
  <img alt="Maturity" src="https://img.shields.io/badge/maturity-alpha-orange?style=flat-square" />

  <!-- badge:build:start -->
  <img alt="Build" src="https://img.shields.io/badge/build-passing-brightgreen?style=flat-square" />
  <!-- badge:build:end -->

  <!-- badge:unit:start -->
  <img alt="Unit Tests" src="https://img.shields.io/badge/unit%20tests-unknown-lightgrey?style=flat-square" />
  <!-- badge:unit:end -->

  <!-- badge:integration:start -->
  <img alt="Integration Tests" src="https://img.shields.io/badge/integration%20tests-passing-brightgreen?style=flat-square" />
  <!-- badge:integration:end -->

  <!-- badge:security:start -->
  <img alt="Security" src="https://img.shields.io/badge/security-unknown-lightgrey?style=flat-square" />
  <!-- badge:security:end -->

  <!-- badge:system:start -->
  <img alt="System Tests" src="https://img.shields.io/badge/system%20tests-unknown-lightgrey?style=flat-square" />
  <!-- badge:system:end -->

  <!-- badge:cov-ym:start -->
  <img alt="Tests Coverage" src="https://img.shields.io/badge/tests%20coverage-unknown-lightgrey?style=flat-square" />
  <!-- badge:cov-ym:end -->
    
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Linux%20%7C%20macOS%20%7C%20Windows-blue?style=flat-square" />

  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-lightgrey?style=flat-square" />
</p>

<img
  src="https://github.com/deeprnd/tickoni-content/blob/main/assets/banners/banner.png"
  alt="A blue oni studying investment charts beside an abacus and coins"
  width="100%"/>

Financial computation already has excellent libraries. The problem is that they exist as separate islands, each with its own API, types, memory model, ownership rules, error handling, threading model, build system, versioning, language bindings, and platform peculiarities.

Yamori exists to build the integration layer once.

**Traditional quantitative libraries implement algorithms. Yamori owns the contract — and delegates the algorithms.**

Build the integration layer once. Use it everywhere.

```text
market prices
→ returns
→ rolling volatility
→ model calibration
→ option valuation
→ scenario risk
→ portfolio analytics
```

## ⚡ One Runtime. No Translation Layers.

What once required writing custom adapters between BLAS, TA-Lib, QuantLib, Cuba, and NumPy now flows through a single stable interface.

Yamori unifies mature specialized libraries behind one coherent runtime:

- One stable C ABI for every runtime capability
- One shared data model (`Buffer` → `Array` → `Series` → `Table`)
- One semantic dispatch layer with zero-copy backend adaptation
- One financial formula dependency graph for compositional pricing and analytics

## 🧠 Composition Before Coverage

Most quantitative libraries measure success by function count. Yamori measures it by composition.

The objective is not to support 10,000 functions. It is to make 100 important functions from ten different domains compose correctly over one representation. Market prices → returns → rolling volatility → model calibration → option valuation → scenario risk — all stages operating over Yamori objects without backend-specific conversion code.

- Financial metrics defined as named dependency graphs resolve in deterministic topological order
- The same graph serves valuation formulas, technical indicators, portfolio operations, integration routines, and pricing functions
- Backend plurality is native: multiple engines can implement the same semantic operation, selected by platform, CPU capabilities, or configured preference

## Core principle

> **Own semantics. Delegate implementation.**

## 🛡️ No Backend Leakage

Yamori functions accept and return Yamori types, never backend types. `yamori.ta.macd()` returns a Yamori Series, not a GSL vector. Backend representations remain private.

**Yamori does not implement:**

- Matrix multiplication (delegated to BLAS/LAPACK)
- Numerical integration (delegated to Cuba)
- Technical indicators (delegated to TA-Lib)
- Financial models (delegated to QuantLib and similar)

Every algorithm — singular value decomposition, Monte Carlo integration, spectral analysis, Black-Scholes pricing, moving averages — is delegated to the appropriate backend. Yamori's job is to make those backends compose over one representation, one ABI, and one memory model.

**Own the contract. Don't reimplement the math.**

## Systems foundation

Yamori's systems foundation originates in Firedancer, Jump Crypto's high-performance Solana systems codebase, shaped by low-latency trading engineering.

Firedancer contributes low-level C infrastructure for high-throughput networking, preallocated memory workspaces, concurrent processing, process isolation, and restrictive sandboxing.

Yamori turns that systems foundation into a quantitative-computing runtime with shared-memory representations for cross-process zero-copy data sharing, unified backend routing, and a financial formula dependency graph.

The result is a system designed to keep the contract, the algorithms, and the data model cleanly separated.

## Status

Yamori is experimental. The runtime foundation and core data model are in place; domain coverage is expanding.

## Documentation

- [Architecture](doc/knowledge/architecture.md)
- [Strategy](doc/strategy/README.md)
- [Development](doc/execution/development.md)

## License

Yamori is released under the [GNU General Public License v3.0](LICENSE).
