# varanos Observability

This document summarizes the current varanos observability surface and the
operator signals expected from the valuation pipeline.

The current repo does not ship a local Prometheus/Grafana/Loki/Tempo Compose
stack for varanos. Phase 0 exposes runtime metrics and diagnostics through the
Zig workspace and in-memory valuation snapshots. The intended production
direction is still a `valmetr`-style metrics module and a `valdiag`-style
diagnostics module, following proven high-performance patterns.

## Principle

No black boxes.

Every pipeline stage, every sourced input, every policy decision, and every
audit check should expose runtime state. Observability is not log text added
after the fact; it is part of the valuation ownership model.

For V1.x retail runtime support, this observability surface remains
local-first and evidence-oriented: CLI host reports, deterministic demo output,
local audit artifacts, provenance chains, and linked conformance evidence.
CaseOps UI surfacing and hosted observability stacks are explicitly deferred
work, not implied current behavior. Both macOS and Windows retail tiers share
the same privacy defaults (telemetry disabled by default, no outbound telemetry
required) and the same evidence-oriented trust surface.

## Current Runtime Commands

Build the varanos workspace:

```bash
zig build
```

Run a valuation with complete inputs:

```bash
zig build run -- val --inputs inputs.json
```

Yamori is a financial library — it does not accept a ticker symbol alone. A
valuation requires full inputs: financial statements (income statement, balance
sheet, cash flow), market data (share price, shares outstanding, risk-free
rate, ERP), geographic exposure, Damodaran sector assignment, peer-set
assignment, and policy choices (R&D life, lease treatment, discount
convention). The `--inputs` flag accepts a JSON file that supplies every field
the `ValuationInputs` struct requires. Without these inputs the engine cannot
run.

Run a deterministic golden-test replay:

```bash
zig build test -- golden
```

The `val` command prints:

- pipeline stage completion states
- valuation metric counters (provenance, adjustments, audit severities)
- diagnostic counters (dataset integrity, gap reporting)
- provenance chain depth

Example output shape:

```text
varanos: Phase 0 valuation completed
stages:
  [0] ingest      state=completed   validated=52 conflicts=2 gaps=3
  [1] resolve     state=completed   resolved=49 conflicts=2
  [2] adjust      state=completed   rnd_capitalized=true leases_capitalized=true
  [3] derive      state=completed   roic_years=5 growth_stages=11
  [4] project     state=completed   projected_years=10 terminal=both
  [5] analyse     state=completed   sensitivity_grid=15 scenarios=4 reverse_dcf=100
  [6] audit       state=completed   checks_run=25 errors=0 warns=2 infos=5
metrics: validated=52 conflicts=2 rnd_adj=1 lease_adj=1 roic_window=5
diag: dataset_checksums_pass=true gap_count=3 gold_hash=blake3:...
varanos: stopped
```

## What Is Exposed

| Signal | Current source | Meaning |
| --- | --- | --- |
| Validated records | `ValuationInputs` provenance | Financial periods and market data accepted by ingest |
| Source conflicts | `resolve` stage | Competing values for the same XBRL element that resolved to different sources |
| Data gaps | `resolve` stage | Required fields absent from every available source |
| R&D capitalized | `adjust` stage | R&D capitalization adjustment applied |
| Leases capitalized | `adjust` stage | Lease capitalization adjustment applied |
| ROIC window | `derive` stage | Number of trailing years used for ROIC statistics |
| Growth stages | `derive` stage | Years in high-growth + transition + terminal |
| Projected years | `project` stage | Number of forward projection years |
| Terminal methods | `project` stage | Both Gordon and exit-multiple methods computed |
| Sensitivity runs | `analyse` stage | Number of sensitivity grid cells re-run |
| Scenario runs | `analyse` stage | Named scenario overrides executed |
| Reverse DCF solves | `analyse` stage | Bisection iterations to find implied growth |
| Audit checks | `audit` stage | Total checks evaluated, by severity |
| Audit errors | `audit` stage | Error-severity checks that block rendering |
| Audit warnings | `audit` stage | Warn-severity checks indicating strain |
| Gold hash | `provenance_hash` | BLAKE3 over canonical inputs, policy, engine version, dataset snapshot |
| Dataset checksums | `manifest.toml` | SHA-256 of every normalized reference dataset file |

## Per-Stage Visibility

Observability follows the pipeline boundary.

Phase 0 stages:

| Stage | Signal focus |
| --- | --- |
| `ingest` | validated records, source conflicts, data gaps, XBRL element coverage |
| `resolve` | source-priority decisions, staleness demotions, conflict disclosures |
| `adjust` | R&D capitalization, lease capitalization, base-year distortion flag |
| `derive` | ROIC window years, growth stages, tax convergence path, currency consistency |
| `project` | projected years, terminal value by method, equity bridge line items |
| `analyse` | sensitivity grid cells, named scenarios, reverse-DCF bisection count |
| `audit` | check severities, blocked verdicts, transparency source coverage |

Future analytics and reporting layers should expose the same bounded categories:

- records or values received
- records or values completed
- failures by bounded kind (missing data, currency mismatch, audit error)
- source-priority decisions and conflict counts
- gap counts by field
- adjustment counts by type
- audit severities
- provenance chain depth
- dataset snapshot vintage

## Smoke Checks

Use the narrowest command that checks the surface you changed:

- `zig build test -- valuation_core` for pure function tests in the core module
- `zig build test -- golden` for deterministic replay against a known company
- `zig build test -- properties` for property-based tests (monotonicity, identity checks)
- `zig build` for the full workspace compile check

## Failure Visibility

Failures are not silent.

The target model is failure-transparent: if a pipeline stage cannot produce a
result, the error is returned as `!Error` and the calling stage reports the
gap. Phase 0 enforces this through the `!Error` convention — no `unreachable`
in library code, and no silent fallback values.

Failure categories to preserve as the architecture hardens:

- missing required financial period (fewer than `history_years`)
- unresolved source conflict exceeding tolerance
- negative base operating income with negative median margin
- stable growth exceeding risk-free rate
- WACC minus stable growth below 100bp
- terminal value numerically unstable (spread too narrow)
- currency mismatch between forecast and discount inputs
- SBC treatment violation (double-counted or missing)
- capitalization adjustment applied partially (EBIT but not invested capital)
- dataset checksum mismatch against manifest

## Related Docs

- [Telemetry](./telemetry.md)
- [Architecture](../knowledge/architecture.md)
- [Valuation Plan](./plans/valuation-plan.md)
