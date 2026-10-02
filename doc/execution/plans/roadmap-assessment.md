# Roadmap Assessment — Yamori Intrinsic Valuation Engine

**Date:** 2025-10-02
**Assessed against:** `doc/strategy/roadmap/milestones/`, `doc/strategy/roadmap/epics/`, `doc/execution/plans/`

## Product definition

Yamori is a native financial computation runtime that gives financial meaning, lineage, reproducibility and a common execution contract to best-in-class quantitative engines.

## Document sets assessed

| Set | Location | Purpose |
|---|--- |--- |
| Strategy positioning | `positioning-v1.md`, `positioning-v2.md`, `library-domains.md` | Yamori product definition — the financial computation runtime, its value proposition, dependency evolution |
| Library roadmap | `library-roadmap.md`, `apache-arrow.md`, `librariy-plan.md` | Dependency evolution sequence (Arrow → GSL → nanoarrow → post-M4 domains) |
| Epics | `doc/strategy/roadmap/epics/V1.1–V5.26` | First domain (Damodaran valuation) — product epics with stories |
| Architecture | `valuation-plan.md` | First domain's implementation — Damodaran engine in Zig |
| Milestones | `doc/strategy/roadmap/milestones/m1.md–m5.md` | Milestone summaries |
| Execution roadmap | `roadmap.md` | Execution plan milestones (M1–M4) with stories |

---

## Findings

### F1. CRITICAL — M5 epic numbering error

`m5.md` lists "V5.23" twice: once for "Valuation report generation" and once for "Historical replay." The epics README correctly shows V5.22 as "Valuation report generation" and V5.23 as "Historical replay." m5.md has no V5.22 and duplicates V5.23.

**Impact:** Story IDs (V5.23.S1, etc.) are ambiguous. Blocker for issue tracking.

### F2. CRITICAL — Financial formula dependency graph is not in the epics

`positioning-v2.md` (§"Financial formula dependency graphs") identifies this as Yamori's strongest differentiator: Yamori knows that `IntrinsicValue depends on FCFF depends on EBIT depends on tax...` and can re-evaluate the graph for sensitivity, Monte Carlo, reverse DCF.

The execution plans mention it in M1 Epic 1.4 ("Named Formula", "Formula Dependencies") but it's buried in the CSV ratio engine. The epics have no "dependency graph" epic. The architecture doc's `runValuation()` is a function call, not a graph traversal.

**Impact:** The epics build a Damodaran pipeline but don't build Yamori's core asset — the graph that makes sensitivity/Monte Carlo/reverse DCF "re-evaluations of the same graph."

### F3. CRITICAL — Monte Carlo epics missing from epic plan

The execution plans M3 (Epic 3.1–3.4: Random Sampling, Monte Carlo Runner, Monte Carlo Summary, Monte Carlo Demo) defines four well-specified epics for stochastic uncertainty. No V3.x epics for Monte Carlo exist in the epics folder. The epics' V3.12–V3.16 cover only deterministic cross-checks (reverse DCF, relative multiples, sensitivity matrices, scenarios, audit checks).

**Impact:** Monte Carlo is the third pillar of the Damodaran methodology (deterministic valuation + cross-checks + uncertainty). The first domain is incomplete without it.

### F4. CRITICAL — Yamori runtime epics absent from the epic plan

`positioning-v2.md` identifies these as Yamori differentiators:
- Financial formula dependency graph
- Consistent null/missing-data semantics
- Consistent provenance
- Deterministic execution policy
- Stable C ABI
- Shared-memory interoperability
- Research → production parity

**None appear as epics.** The execution plan's M4 (Epic 4.1–4.6) covers some but frames them as a "refactor" of existing code, not as Yamori capabilities.

**Impact:** The epics build Damodaran features on direct Arrow/GSL calls. M4 then restructures them. This is backwards from the product strategy: the runtime should be built first, then proven with domains.

### F5. HIGH — M1/M2 numbering misalignment between execution plans and epics

| | Execution plan M1 | Execution plan M2 |
|---|---|---|
| Content | CSV Ratio Engine (Arrow only) | Damodaran Valuation Math (Arrow + GSL) |
| Epics equivalent | V2.6 (XBRL mapping) | V1.1–V1.5 + V3.12–V3.15 |

| | Epics M1 | Epics M2 |
|---|---|---|
| Content | Valuation Engine Core (WACC, growth, FCFF, terminal) | Financial Statement Ingestion (XBRL, R&D, leases, SBC, TTM) |
| Execution plan equivalent | Epic 2.1–2.7 | Epic 1.x (CSV/ratio engine) |

**Impact:** Two different M1s and M2s with different content. Engineers cannot correlate epics to execution plans without manual mapping.

### F6. HIGH — Library dependencies not traced into epic scope

The library-roadmap.md defines a dependency sequence: M1 = Arrow only, M2 = Arrow + GSL, M3 = + RNG/distributions, M4 = + nanoarrow, post-M4 = TA-Lib/QuantLib/BLAS/Cuba/FFTW.

No dependency information appears in the epic files. An engineer reading epics alone wouldn't know:
- V1.1–V1.5 should use Arrow Compute (not GSL)
- V1.2.S5 "historical median via GSL" is the first GSL dependency
- V3.12 "fixed-count bisection" requires GSL Roots
- C ABI doesn't exist until post-M1–M3

**Impact:** Epic scope sections describe WHAT but not which backend/library each story should use.

### F7. HIGH — "Deterministic execution" — tested but not built as a capability

`positioning-v2.md` (§"Deterministic execution") identifies this as "one of the hardest claims Yamori could make." Requires: pinned algorithms, pinned RNG, explicit seed, pinned threading policy, specified reduction order, fast-math disabled.

The architecture doc handles this via decisions (D3, D20, D21, D3b) but there's no epic that says "Implement deterministic execution policy." The epics have "bit-identity test" (V1.1.S4) which tests it but doesn't build the policy infrastructure.

**Impact:** Deterministic execution is a collection of tests and decisions, not a built capability.

### F8. HIGH — Research → production parity not tracked

`positioning-v2.md` (§"Research → production parity") is identified as "potentially a very strong reason for Yamori." Python notebook and Zig production call the same native function, same graph, same backend versions.

No epic addresses this. The architecture doc has Phase 6 (CLI + MCP server) and mentions Python in the C ABI section, but there's no epic for the multi-language surface. All epics are Zig-focused.

**Impact:** Without a "multi-language surface" epic, the research→production parity claim is not validated.

### F9. HIGH — Execution plan M4 epics should be Yamori capability epics

The execution plan's M4 (Epic 4.1–4.6) covers:
- Unified Arrow Memory Model (4.1)
- Unified Backend Router (4.2)
- Shared-memory Representation (4.3)
- C ABI (4.4)
- Unified Build (4.5)
- Refactor Parity (4.6)

These describe Yamori runtime capabilities. But they live in the execution plans, not the epics folder. And they're framed as "refactor parity" — proving that restructuring doesn't change outputs — rather than as product capabilities.

**Impact:** These should be elevated to Yamori capability epics with proper product narratives, or explicitly traced to runtime epics.

### F10. MODERATE — Post-M4 domains have no epic home

The library roadmap defines post-M4 domains:
- TA-Lib → technical indicators (MACD, RSI, Bollinger Bands, etc.)
- QuantLib → options, derivatives, fixed income
- BLAS/LAPACK → portfolio analytics, factor models
- Cuba → multidimensional integration
- FFTW → spectral analytics

None appear in the epics or any planning doc. No "future domains" section in the epics README.

**Impact:** Future capability expansion has no tracking mechanism.

### F11. MODERATE — M1/M2 milestone title inconsistency

`m1.md` is titled "M1: Damodaran Core — Intrinsic Value Engine" but the epics README lists it as "Milestone 1: Valuation Engine Core." The m1.md milestone README table says "M1: Grounded Valuation" but the actual file has a different title.

**Impact:** Cosmetic inconsistency; minor confusion for cross-referencing.

### F12. MODERATE — V2.1–V2.5 numbering gap

M1 epics go V1.1–V1.5. M2 epics jump to V2.6–V2.11. The numbering implies V2.1–V2.5 are missing. The epics README shows V2.6 as the first M2 epic. This is likely intentional (epics were added to an existing backlog) but creates ambiguity.

**Impact:** Confusion in cross-referencing; low severity but should be documented.

### F13. POSITIVE — Damodaran domain epics are well-structured

Each epic has: Product Intent, Users/Jobs, Success Metrics, Demo Moment, Scope (In/Out), Boundary Checklist, Story Breakdown with decomposition rules, Epic Acceptance, Release/Evidence Gate, Dependencies.

Decomposition rules are clear: independent delivery, one capability per story, closure story. Boundary checklist is consistent (financial capability, audit, replay, runtime topology, security, etc.). Success metrics are specific and testable (compile-time currency mixing failure, bit-identity across four platforms, golden test within 0.01%).

V1.1 through V1.5 together deliver a complete Damodaran DCF — the execution plan's M2 content.

### F14. POSITIVE — Architecture doc (valuation-plan.md) is tight

24 decisions (D1–D24) that are specific, actionable, and traceable. 22 audit checks (§7) are severity-classified and methodology-grounded. §3 data integrity issues (CRP vs default spread, unit mismatches, column headers, shape irregularities) are real engineering problems. Module architecture (§5) enforces purity structurally.

---

## Required actions

| Priority | Action |
|----------|--------|
| Critical | Add Yamori runtime epics: dependency graph, backend router, null semantics, provenance system, deterministic execution policy |
| Critical | Add Monte Carlo epics (V3.x) — 4 epics defined in execution plans M3 |
| Critical | Elevate execution plan M4 epics from "refactor" to Yamori capability epics |
| High | Create "Yamori roadmap" mapping epics to dependency evolution (Arrow→GSL→nanoarrow→domains) |
| High | Trace library dependencies into epic scope sections |
| High | Add "Research → Production Parity" epic or track as epic-level outcome |
| Medium | Fix M5 numbering (V5.22/V5.23) |
| Medium | Add "Future Domains" section to epics README |
| Low | Resolve M1/M2 numbering misalignment |
