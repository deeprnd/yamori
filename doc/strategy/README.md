# Yamori Strategy

## Purpose

This directory owns Yamori product strategy: what the product is, who it is
for, how the roadmap is organized, and where product decisions should be made.
Architecture, valuation methodology, and implementation details remain in the
knowledge and execution docs.

## What Yamori Is

Yamori is a rigorous, Damodaran-style intrinsic valuation engine.

It performs FCFF-based discounted cash flow valuations using Aswath Damodaran's
published framework, grounded in real financial data and auditable assumptions.

Yamori:

- Collects and validates company financial statements from primary sources
- Applies consistent accounting adjustments (R&D capitalization, lease
  capitalization, SBC treatment)
- Computes WACC with currency-matched risk-free rates and revenue-weighted
  country risk premiums
- Builds three-stage growth models from fundamentals (ROIC × reinvestment),
  not extrapolation
- Cross-checks with reverse DCF, relative multiples, and scenario analysis
- Produces transparent, reproducible valuation output with full data provenance

The core rule is:

> Every input must be grounded in data. Every assumption must be traceable to
> a source and date. Every output must be reproducible by someone with the
> same inputs.

## What Yamori Is Not

Yamori is not:

- a trading recommendation engine
- a portfolio manager or robo-advisor
- a real-time quote or market data platform
- a technical analysis tool
- a sentiment or news analysis engine
- a generic financial calculator
- a model that replaces human judgment — it structures it

Yamori is built for investors and analysts who need rigorous, auditable,
reproducible intrinsic valuations — not opinions dressed as analysis.

## Core Principles

1. **Grounded inputs.** No assumption pulled from thin air. Discount rates from
   CAPM + WACC formulas. Growth from fundamentals (ROIC × reinvestment).
2. **Consistency.** Nominal cash flows with nominal discount rates. Growth
   matched to reinvestment. One currency throughout the forecast.
3. **Every input traceable.** Source and date for every number. If the latest
   data cannot be found, state the reporting period used.
4. **Reproducible.** Anyone with the same inputs should arrive at the same
   valuation. Show the work, not just the answer.
5. **Transparent about uncertainty.** Show the range, not just the point
   estimate. Run sensitivity and scenario analysis.
6. **SBC is real.** Stock-based compensation is an operating expense — never
   add it back. Value outstanding options and RSUs explicitly and deduct them.

## Source Of Truth

| Document | Owns | Does not own |
| --- | --- | --- |
| [`README.md`](README.md) | Product identity, strategy directory guide, what Yamori is | Valuation methodology, implementation tasks |
| [`positioning.md`](positioning.md) | Market position, differentiation, buyer framing | Delivery sequencing or implementation tasks |
| [`roadmap/`](roadmap/) | Versioned milestones, story files, evidence gates, increment status | Market narrative or methodology decisions |
| [`templates/`](templates/) | GitHub issue templates for epics, stories, tasks, proposals, and status | Valuation methodology source of truth |
| [`capabilities.md`](capabilities.md) | Supported valuation workflows, input types, output formats | Implementation-specific tile APIs |
| [`doc/knowledge/architecture.md`](../knowledge/architecture.md) | System layers, data flow, source-of-truth boundaries | Product backlog sequencing |

## Product Operating Model

### Planning Cadence

- Roadmap review: update when product priority, version order, or strategic
  scope changes.
- Story grooming: update when stories split, merge, or change acceptance
  criteria.
- Methodology review: update when Damodaran framework changes or new
  accounting adjustments are adopted.

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

## Status

The current repository contains Yamori's Damodaran-style DCF valuation engine.
The active implementation processes financial statements, computes WACC, builds
three-stage growth models, and produces per-share intrinsic value estimates
with full cross-checks and sensitivity analysis.
