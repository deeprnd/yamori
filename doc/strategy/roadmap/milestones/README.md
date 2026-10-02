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
| [M1](m1.md): Grounded Valuation | FCFF-based DCF with WACC, three-stage growth, and per-share intrinsic value |
| [M2](m2.md): Data-In-Data-Out | Financial statement ingestion, validation, and accounting adjustment pipeline |
| [M3](m3.md): Cross-Checks And Uncertainty | Reverse DCF, relative multiples, sensitivity tables, and scenario analysis |
| [M4](m4.md): Comparative Analysis | Multi-company peer benchmarking and valuation spreads |
| [M5](m5.md): Reports And Replay | Exportable valuation reports, historical replay, and backtesting |

## Cross-References

- Product bet, target user, and priority stack: [`positioning.md`](../../positioning.md).
- Methodology decisions: [`doc/knowledge/architecture.md`](../../../knowledge/architecture.md).
- Coding conventions: [`execution/contribution/yamori.md`](../../../execution/contribution/yamori.md).
