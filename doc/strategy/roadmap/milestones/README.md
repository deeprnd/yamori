# Milestones — Yamori Intrinsic Valuation Engine

The valuation roadmap is grouped into higher-level milestones.
These files provide the milestone view only; the increment files under
[`epics/README.md`](../epics/README.md) remain the source of truth for
version order, product narrative, priority tradeoffs, and increment detail.

Use this folder when the question is:

```text
Which larger product milestones do the roadmap epics roll up into?
```

An "epic" here means a named roadmap increment such as `V0.1` or a
carried-forward platform backlog item.

## Milestones

| Milestone | Product result |
| --- | --- |
| [M1](m1.md): Yamori Runtime Foundation | Dependency graph, backend router, shared memory, C ABI, deterministic execution |
| [M2](m2.md): Damodaran Valuation Engine | FCFF-based DCF with WACC, three-stage growth, and per-share intrinsic value |
| [M3](m3.md): Financial Statement Ingestion | XBRL mapping, R&D/lease/SBC adjustments, base-year normalization, TTM resolution |
| [M4](m4.md): Cross-Checks and Monte Carlo | Reverse DCF, sensitivity matrices, scenarios, Monte Carlo uncertainty, audit checks |
| [M5](m5.md): Comparative Analysis and Reports | Peer benchmarking, valuation reports, historical replay, audit trails, CLI |
| [M6](m6.md): Technical Analysis | TA-Lib indicators: moving averages, oscillators, volatility, volume, patterns |
| [M7](m7.md): Options and Derivatives | QuantLib: options pricing, fixed income, volatility surfaces, yield curves |
| [M8](m8.md): Portfolio Analytics | BLAS/LAPACK: factor models, risk decomposition, mean-variance optimization |
| [M9](m9.md): Advanced Analytics | Cuba: multidimensional integration, FFTW: spectral analysis and cycle detection |

## Cross-References

- Product bet, target user, and priority stack: [`positioning.md`](../../positioning.md).
- Methodology decisions: [`doc/knowledge/architecture.md`](../../../knowledge/architecture.md).
- Coding conventions: [`execution/contribution/yamori.md`](../../../execution/contribution/yamori.md).
