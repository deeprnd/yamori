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

### Milestone 1: Valuation Engine Core

| Epic | Description |
| --- | --- |
| [V1.1](V1.1.md) | WACC computation and discount rate framework |
| [V1.2](V1.2.md) | Historical metrics, median margin, and sustainable growth |
| [V1.3](V1.3.md) | Three-stage growth model and FCFF projection |
| [V1.4](V1.4.md) | Base-year EBIT and present value of ten-year FCFF |
| [V1.5](V1.5.md) | Terminal value, equity bridge, and per-share intrinsic value |

### Milestone 2: Financial Statement Ingestion and Adjustments

| Epic | Description |
| --- | --- |
| [V2.6](V2.6.md) | Financial statement ingestion and XBRL mapping |
| [V2.7](V2.7.md) | R&D capitalization adjustment |
| [V2.8](V2.8.md) | Lease capitalization adjustment |
| [V2.9](V2.9.md) | Stock-based compensation and diluted shares |
| [V2.10](V2.10.md) | Base-year normalization and distortion detection |
| [V2.11](V2.11.md) | TTM calculation and source-priority resolution |

### Milestone 3: Cross-Checks and Uncertainty

| Epic | Description |
| --- | --- |
| [V3.12](V3.12.md) | Reverse DCF — implied growth rate from market price |
| [V3.13](V3.13.md) | Relative-multiple cross-checks (P/E, P/S, EV/EBITDA) |
| [V3.14](V3.14.md) | Sensitivity matrices — WACC/growth grid |
| [V3.15](V3.15.md) | Scenario analysis — bull, base, bear, stress |
| [V3.16](V3.16.md) | Audit checks and severity enforcement |

### Milestone 4: Comparative Analysis — Multi-Company Benchmarking

| Epic | Description |
| --- | --- |
| [V4.17](V4.17.md) | Peer-set management and company catalog |
| [V4.18](V4.18.md) | Batch valuation runner |
| [V4.19](V4.19.md) | Relative valuation metrics (discount/premium, percentiles) |
| [V4.20](V4.20.md) | Valuation spread visualization |
| [V4.21](V4.21.md) | Sector-relative positioning |

### Milestone 5: Reports and Replay — Export, Historical Validation, Audit

| Epic | Description |
| --- | --- |
| [V5.22](V5.22.md) | Valuation report generation |
| [V5.23](V5.23.md) | Historical replay and backtesting |
| [V5.24](V5.24.md) | Deterministic audit trail and provenance hash |
| [V5.25](V5.25.md) | Dataset versioning and manifest management |
| [V5.26](V5.26.md) | CLI and export interfaces |

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
