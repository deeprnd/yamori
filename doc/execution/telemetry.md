# Telemetry

This document focuses on varanos runtime metrics, diagnostics, and telemetry
semantics.

The current varanos implementation exposes telemetry as in-memory snapshots and
CLI output. It does not yet expose a Prometheus-compatible scrape endpoint.
The existing metrics substrate remains under `src/disco/metrics` and
should be reused where practical when a `valmetr` module becomes a production
metrics module for varanos.

## Current Endpoints

There are no varanos-specific Prometheus endpoints in the current Phase 0
workspace.

The only telemetry output is the final metric line printed after the valuation
completes (full inputs supplied via `--inputs` flag).

## Retail Runtime Privacy Defaults

V1.x retail runtime support is local-first:

- installer telemetry is disabled by default
- `varanos --version`, `varanos doctor`, and the deterministic valuation flows do not
  require outbound telemetry
- evidence generation (provenance chains, audit records, dataset manifests) is local/offline by default
- a later story may add opt-in diagnostics or managed export, but V1.x does
  not claim that remote telemetry is part of the retail support path

The retail trust surface is therefore inspectable without network-side
collection, background exporters, or hosted analytics dependencies.

Current manual telemetry output is available through:

```bash
zig build run -- val --inputs inputs.json
```

The command prints a final metric line and diagnostic line after the valuation
pipeline completes.

## Implementation Locations

Varanos telemetry lives in:

- `src/valuation_core/provenance.zig` — `DataPoint<T>` provenance, provenance hash
- `src/valuation_core/audit.zig` — audit check results, severity counts
- `src/app/varanos/main.zig` — CLI entry point, pipeline orchestration, output rendering
- `src/valuation_data/manifest.zig` — dataset checksum verification, snapshot metadata

Architecture and expected module ownership are documented in:

- `doc/architecture.md`
- `doc/execution/plans/valuation-plan.md`
- `doc/strategy/positioning.md`

## Phase 0 Metrics

The `ValuationResult` carries these low-cardinality runtime signals:

| Field | Type | Meaning |
| --- | --- | --- |
| `validated` | counter | Financial periods and market data records accepted by ingest |
| `conflicts` | counter | Competing source values that resolved to different sources |
| `gaps` | counter | Required fields absent from every available source |
| `rnd_capitalized` | boolean gauge | Whether R&D capitalization was applied |
| `leases_capitalized` | boolean gauge | Whether lease capitalization was applied |
| `roic_window` | gauge | Number of trailing years used for ROIC statistics |
| `growth_stages` | gauge | Total years across high-growth, transition, and terminal |
| `projected_years` | gauge | Number of forward projection years |
| `terminal_methods` | gauge | Count of terminal methods computed (should be 2: Gordon + exit) |
| `sensitivity_runs` | counter | Number of sensitivity grid cells re-run |
| `scenario_runs` | counter | Named scenario overrides executed |
| `reverse_dcf_iterations` | counter | Bisection iterations for implied growth solve |
| `audit_checks_run` | counter | Total audit checks evaluated |
| `audit_errors` | counter | Error-severity checks that block rendering |
| `audit_warnings` | counter | Warn-severity checks indicating methodology strain |
| `audit_infos` | counter | Info-severity checks for convention or selection records |
| `provenance_hash` | hash | BLAKE3 over canonical inputs, policy, engine version, dataset snapshot |

These are low-cardinality runtime signals. They are suitable for future
Prometheus counters, gauges, and a summary metric.

## Phase 0 Diagnostics

The diagnostics reported at the end of a valuation:

| Field | Type | Meaning |
| --- | --- | --- |
| `dataset_checksums_pass` | boolean gauge | Whether every normalized reference dataset matches its manifest SHA-256 |
| `dataset_vintage` | string | Version identifier of the reference dataset snapshot used |
| `gap_count` | gauge | Number of required fields that have no sourced input |
| `gap_details` | list of strings | Which fields are missing (for audit trails) |
| `gold_hash` | hash | Reproducibility hash for golden-test comparison |
| `blocked_verdict` | boolean gauge | Whether any Error-severity audit check failed |
| `currency_consistent` | boolean gauge | Whether forecast currency, discount rate, and output share one currency |
| `base_year_normalized` | boolean gauge | Whether the base year was flagged as distorted and normalized |

The CLI prints these diagnostics at the end of the valuation pipeline.

## Alerting Policy

No varanos alert rules are committed yet.

Future alerting should use a bounded severity taxonomy:

| Severity | Meaning |
| --- | --- |
| `critical` | Active data integrity failure, audit Error verdict, dataset checksum mismatch, or valuation that blocks rendering needing immediate action |
| `warning` | Degraded data quality, sustained gap count, terminal value share >75%, or methodology warnings needing operator attention soon |
| `info` | Non-paging operational signal for awareness, provenance correlation, or audit trails |

Phase 0 signals that should become alert sources once a metrics endpoint and
rule files exist:

- dataset checksum mismatch (reference data corruption)
- audit Error verdict (methodology violation, blocked result)
- stable growth exceeding risk-free rate (numerical instability)
- WACC minus stable growth below 100bp (terminal value instability)
- currency mismatch (forecast vs discount vs output)
- SBC treatment violation (double-counting or missing deduction)
- partial capitalization (EBIT adjusted but invested capital not)
- sustained gap count across multiple fields
- base-year distortion without normalization

## Retail Runtime Privacy Defaults (V1.x)

V1.x retail runtime support shares the same privacy defaults across platforms:

- **Telemetry is disabled by default** on all retail tiers
- `varanos --version`, `varanos doctor`, and deterministic valuation flows do not
  require outbound telemetry
- Evidence generation is local/offline by default (provenance, audit, dataset manifests)
- A later story may add opt-in diagnostics or managed export, but V1.x does
  not claim that remote telemetry is part of the retail support path
- Valuation inputs are sourced from the user's filings or manual entry — no
  background data collection
- The retail trust surface is inspectable without network-side collection,
  background exporters, or hosted analytics dependencies

## Label Policy

Telemetry in this repo must stay low-cardinality and audit-friendly.

Allowed future label shapes:

- `stage` — pipeline stage name (ingest, resolve, adjust, derive, project, analyse, audit)
- `adjustment_type` — R&D, leases, goodwill, tax convergence
- `currency` — ISO 4217 currency code
- `failure_kind` — missing_data, currency_mismatch, audit_error, checksum_fail
- `severity` — Error, Warn, Info
- `dataset` — reference dataset name (us_implied_erp, global_betas, etc.)

Do not put high-cardinality identifiers into metric labels. These belong in
audit records, provenance records, or evidence stores instead.

Forbidden examples:

- company ticker symbols (beyond a fixed set of sample companies)
- filing document IDs
- XBRL element names beyond the fixed schema
- raw financial values or per-share prices
- raw model output or generated text
- raw error messages
- stack traces

## Generated Metrics

If metrics definitions under `src/disco/metrics/metrics.xml` change,
regenerate metrics with:

```bash
make -C src/disco/metrics metrics
```

This regenerates files under:

- `src/disco/metrics/generated/`
- `book/api/metrics-generated.md`

Generated outputs are checked into the repository.

## Determinism Contract

The determinism contract (valuation-plan.md §6) applies to telemetry as well.

Every metric output is a pure function of its inputs. The `provenance_hash`
ensures that two runs with the same hash produce bit-identical metrics. Golden
tests assert on the hash rather than on individual metric values, so a dataset
refresh that changes a benchmark value will fail the golden test and be visible
in the metrics delta.

## Related Docs

- [Observability](./observability.md)
- [Architecture](../knowledge/architecture.md)
- [Valuation Plan](./plans/valuation-plan.md)
