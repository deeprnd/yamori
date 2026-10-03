# Epic Rename Plan: Global Sequential Y Numbering

## Objective

Renumber all epics so Y is a global sequential counter across all milestones.
- Milestone 1 epics: V1.1 through V1.5 (unchanged — Y starts at 1)
- Milestone 2 epics: start at V2.6 (1+5) through V2.10
- Milestone 3 epics: start at V3.11 (10+1) through V3.16
- And so on — each milestone picks up where the previous left off

This creates a single global sequence: V1.1, V1.2, ..., V1.5, V2.6, V2.7, ..., V2.10, V3.11, ...

**Total epics: 59**

## Pre-flight: Known Issue

**M7/M8 are swapped in the epics README.md.** The epics README lists Milestone 7 as "Options and Derivatives" (QuantLib) and Milestone 8 as "Portfolio Analytics" (BLAS/LAPACK). But the milestone files (m7.md, m8.md) and epic file headers correctly describe M7 as BLAS/LAPACK portfolio analytics and M8 as Cuba/FFTW advanced analytics. The README table of contents has the milestone descriptions swapped — the epics themselves are correctly labeled.

**The rename plan below uses the correct mapping** (m7.md/m8.md as truth):
- M7 = BLAS/LAPACK (V7.1–V7.7)
- M8 = Cuba/FFTW (V8.1–V8.6)

The README swap is a separate fix that must be addressed during this rename.

**Note:** V8.7 appears in the README table of contents but no file exists on disk. Plan for this.

## Global Renumbering Map

### Milestone 1 (5 epics, counter 1–5) — UNCHANGED

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V1.1 | V1.1 | (same) |
| V1.2 | V1.2 | (same) |
| V1.3 | V1.3 | (same) |
| V1.4 | V1.4 | (same) |
| V1.5 | V1.5 | (same) |

Counter after M1: **5**

### Milestone 2 (5 epics, counter 6–10)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V2.1 | V2.6 | `mv V2.1.md V2.6.md` |
| V2.2 | V2.7 | `mv V2.2.md V2.7.md` |
| V2.3 | V2.8 | `mv V2.3.md V2.8.md` |
| V2.4 | V2.9 | `mv V2.4.md V2.9.md` |
| V2.5 | V2.10 | `mv V2.5.md V2.10.md` |

Counter after M2: **10**

### Milestone 3 (6 epics, counter 11–16)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V3.6 | V3.11 | `mv V3.6.md V3.11.md` |
| V3.7 | V3.12 | `mv V3.7.md V3.12.md` |
| V3.8 | V3.13 | `mv V3.8.md V3.13.md` |
| V3.9 | V3.14 | `mv V3.9.md V3.14.md` |
| V3.10 | V3.15 | `mv V3.10.md V3.15.md` |
| V3.11 | V3.16 | `mv V3.11.md V3.16.md` |

Counter after M3: **16**

### Milestone 4 (9 epics, counter 17–25)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V4.12 | V4.17 | `mv V4.12.md V4.17.md` |
| V4.13 | V4.18 | `mv V4.13.md V4.18.md` |
| V4.14 | V4.19 | `mv V4.14.md V4.19.md` |
| V4.15 | V4.20 | `mv V4.15.md V4.20.md` |
| V4.16 | V4.21 | `mv V4.16.md V4.21.md` |
| V4.17 | V4.22 | `mv V4.17.md V4.22.md` |
| V4.18 | V4.23 | `mv V4.18.md V4.23.md` |
| V4.19 | V4.24 | `mv V4.19.md V4.24.md` |
| V4.20 | V4.25 | `mv V4.20.md V4.25.md` |

Counter after M4: **25**

### Milestone 5 (9 epics, counter 26–34)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V5.21 | V5.26 | `mv V5.21.md V5.26.md` |
| V5.22 | V5.27 | `mv V5.22.md V5.27.md` |
| V5.23 | V5.28 | `mv V5.23.md V5.28.md` |
| V5.24 | V5.29 | `mv V5.24.md V5.29.md` |
| V5.25 | V5.30 | `mv V5.25.md V5.30.md` |
| V5.26 | V5.31 | `mv V5.26.md V5.31.md` |
| V5.27 | V5.32 | `mv V5.27.md V5.32.md` |
| V5.28 | V5.33 | `mv V5.28.md V5.33.md` |
| V5.29 | V5.34 | `mv V5.29.md V5.34.md` |

Counter after M5: **34**

### Milestone 6 (6 epics, counter 35–40)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V6.1 | V6.35 | `mv V6.1.md V6.35.md` |
| V6.2 | V6.36 | `mv V6.2.md V6.36.md` |
| V6.3 | V6.37 | `mv V6.3.md V6.37.md` |
| V6.4 | V6.38 | `mv V6.4.md V6.38.md` |
| V6.5 | V6.39 | `mv V6.5.md V6.39.md` |
| V6.6 | V6.40 | `mv V6.6.md V6.40.md` |

Counter after M6: **40**

### Milestone 7 (7 epics, counter 41–47)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V7.1 | V7.41 | `mv V7.1.md V7.41.md` |
| V7.2 | V7.42 | `mv V7.2.md V7.42.md` |
| V7.3 | V7.43 | `mv V7.3.md V7.43.md` |
| V7.4 | V7.44 | `mv V7.4.md V7.44.md` |
| V7.5 | V7.45 | `mv V7.5.md V7.45.md` |
| V7.6 | V7.46 | `mv V7.6.md V7.46.md` |
| V7.7 | V7.47 | `mv V7.7.md V7.47.md` |

Counter after M7: **47**

### Milestone 8 (6 epics, counter 48–53)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V8.1 | V8.48 | `mv V8.1.md V8.48.md` |
| V8.2 | V8.49 | `mv V8.2.md V8.49.md` |
| V8.3 | V8.50 | `mv V8.3.md V8.50.md` |
| V8.4 | V8.51 | `mv V8.4.md V8.51.md` |
| V8.5 | V8.52 | `mv V8.5.md V8.52.md` |
| V8.6 | V8.53 | `mv V8.6.md V8.53.md` |

Counter after M8: **53**

### Milestone 9 (6 epics, counter 54–59)

| Old ID | New ID | File Rename |
|--------|--------|-------------|
| V9.1 | V9.54 | `mv V9.1.md V9.54.md` |
| V9.2 | V9.55 | `mv V9.2.md V9.55.md` |
| V9.3 | V9.56 | `mv V9.3.md V9.56.md` |
| V9.4 | V9.57 | `mv V9.4.md V9.57.md` |
| V9.5 | V9.58 | `mv V9.5.md V9.58.md` |
| V9.6 | V9.59 | `mv V9.6.md V9.59.md` |

Counter after M9: **59**

## Files to Update (Internal Epic References)

After renaming files, every epic file contains internal references to other epics. These must be updated to use new IDs. The categories:

### A. Header references (within each epic file)
- `M1 Epic V1.2` → `M1 Epic V1.2` (unchanged)
- `M1 Epic V1.3` → `M1 Epic V1.3` (unchanged)
- No M1 epics change, so all M1 references stay the same.

### B. Cross-milestone dependencies (within each epic file)
Examples of changes needed:
- `V2.1` → `V2.6` (appears in V2.2, V2.3, V2.4, V2.5, V4.14, V5.23, V2.1's own deps)
- `V2.2` → `V2.7`, `V2.3` → `V2.8`, `V2.4` → `V2.9`, `V2.5` → `V2.10`
- `V3.6` → `V3.11`, `V3.7` → `V3.12`, `V3.8` → `V3.13`, `V3.9` → `V3.14`, `V3.10` → `V3.15`, `V3.11` → `V3.16`
- `V4.12` → `V4.17`, `V4.13` → `V4.18`, `V4.14` → `V4.19`, `V4.15` → `V4.20`, `V4.16` → `V4.21`, `V4.17` → `V4.22`, `V4.18` → `V4.23`, `V4.19` → `V4.24`, `V4.20` → `V4.25`
- `V5.21` → `V5.26`, ..., `V5.29` → `V5.34`
- `V6.1` → `V6.35`, ..., `V6.6` → `V6.40`
- `V7.1` → `V7.41`, ..., `V7.7` → `V7.47`
- `V8.1` → `V8.48`, ..., `V8.6` → `V8.53`
- `V9.1` → `V9.54`, ..., `V9.6` → `V9.59`

### C. Story ID references within epic files
- `V2.1.S1` → `V2.6.S1`, etc. (story IDs within renamed epics)
- `V4.14.S1` → `V4.19.S1`, etc.
- These are in the "Story Breakdown" section and in "Dependencies And Decisions"

### D. Ranges like `V2.1–V2.5` → `V2.6–V2.10`
- `V2.1–V2.5` → `V2.6–V2.10`
- `V3.6–V3.11` → `V3.11–V3.16`
- `V4.12–V4.20` → `V4.17–V4.25`
- `V5.21–V5.29` → `V5.26–V5.34`
- `V6.1–V6.6` → `V6.35–V6.40`
- `V7.1–V7.7` → `V7.41–V7.47`
- `V8.1–V8.6` → `V8.48–V8.53`
- `V9.1–V9.6` → `V9.54–V9.59`
- `V4.14–V4.15` → `V4.19–V4.20`
- `V4.17–V4.20` → `V4.22–V4.25`
- `V2.1–V2.2` → `V2.6–V2.7`
- etc.

### E. References to specific stories: `VX.Y.SN`
- Every `VX.Y.SN` reference must have X.Y replaced with the new mapping
- e.g., `V2.2.S1` → `V2.7.S1`, `V4.17.S1` → `V4.22.S1`
- Ranges: `V2.2.S1–S5` → `V2.7.S1–S5`, `V4.14.S1–S3` → `V4.19.S1–S3`

### F. Epic titles within files
- `# V2.2: Historical Metrics and ROIC` in V2.7.md (renamed from V2.2.md) — title stays as the new ID `# V2.7: Historical Metrics and ROIC`
- `# V4.14: Sensitivity Matrices` in V4.19.md → `# V4.19: Sensitivity Matrices`

## Files to Update (Milestone Documents)

Each milestone file (m1.md through m9.md) references epics by their old IDs in the "Epic Vx.y — Title" headers and in cross-reference text.

### m1.md (M1) — No ID changes needed (V1.1–V1.5 unchanged)

### m2.md (M2)
- `### Epic V2.1 — ...` → `### Epic V2.6 — ...`
- `### Epic V2.2 — ...` → `### Epic V2.7 — ...`
- `### Epic V2.3 — ...` → `### Epic V2.8 — ...`
- `### Epic V2.4 — ...` → `### Epic V2.9 — ...`
- `### Epic V2.5 — ...` → `### Epic V2.10 — ...`
- Cross-reference text: `V2.1 through V2.5` → `V2.6 through V2.10`

### m3.md (M3)
- `### Epic V3.6 — ...` → `### Epic V3.11 — ...`
- `### Epic V3.7 — ...` → `### Epic V3.12 — ...`
- `### Epic V3.8 — ...` → `### Epic V3.13 — ...`
- `### Epic V3.9 — ...` → `### Epic V3.14 — ...`
- `### Epic V3.10 — ...` → `### Epic V3.15 — ...`
- `### Epic V3.11 — ...` → `### Epic V3.16 — ...`

### m4.md (M4)
- `### Epic V4.12 — ...` → `### Epic V4.17 — ...`
- `### Epic V4.13 — ...` → `### Epic V4.18 — ...`
- `### Epic V4.14 — ...` → `### Epic V4.19 — ...`
- `### Epic V4.15 — ...` → `### Epic V4.20 — ...`
- `### Epic V4.16 — ...` → `### Epic V4.21 — ...`
- `### Epic V4.17 — ...` → `### Epic V4.22 — ...`
- `### Epic V4.18 — ...` → `### Epic V4.23 — ...`
- `### Epic V4.19 — ...` → `### Epic V4.24 — ...`
- `### Epic V4.20 — ...` → `### Epic V4.25 — ...`

### m5.md (M5)
- `### Epic V5.21 — ...` → `### Epic V5.26 — ...`
- `### Epic V5.22 — ...` → `### Epic V5.27 — ...`
- `### Epic V5.23 — ...` → `### Epic V5.28 — ...`
- `### Epic V5.24 — ...` → `### Epic V5.29 — ...`
- `### Epic V5.25 — ...` → `### Epic V5.30 — ...`
- `### Epic V5.26 — ...` → `### Epic V5.31 — ...`
- `### Epic V5.27 — ...` → `### Epic V5.32 — ...`
- `### Epic V5.28 — ...` → `### Epic V5.33 — ...`
- `### Epic V5.29 — ...` → `### Epic V5.34 — ...`

### m6.md (M6)
- `### Epic V6.1 — ...` → `### Epic V6.35 — ...`
- `### Epic V6.2 — ...` → `### Epic V6.36 — ...`
- `### Epic V6.3 — ...` → `### Epic V6.37 — ...`
- `### Epic V6.4 — ...` → `### Epic V6.38 — ...`
- `### Epic V6.5 — ...` → `### Epic V6.39 — ...`
- `### Epic V6.6 — ...` → `### Epic V6.40 — ...`

### m7.md (M7)
- `### Epic V7.1 — ...` → `### Epic V7.41 — ...`
- `### Epic V7.2 — ...` → `### Epic V7.42 — ...`
- `### Epic V7.3 — ...` → `### Epic V7.43 — ...`
- `### Epic V7.4 — ...` → `### Epic V7.44 — ...`
- `### Epic V7.5 — ...` → `### Epic V7.45 — ...`
- `### Epic V7.6 — ...` → `### Epic V7.46 — ...`
- `### Epic V7.7 — ...` → `### Epic V7.47 — ...`
- Cross-ref text: `M1 Epic V1.1` → unchanged, `M1 Epic V1.2` → unchanged, `M1 Epic V1.3` → unchanged
- `V7.1–V7.7` → `V7.41–V7.47`
- `V7.6–V7.7` → `V7.46–V7.47`

### m8.md (M8)
- `### Epic V8.1 — ...` → `### Epic V8.48 — ...`
- `### Epic V8.2 — ...` → `### Epic V8.49 — ...`
- `### Epic V8.3 — ...` → `### Epic V8.50 — ...`
- `### Epic V8.4 — ...` → `### Epic V8.51 — ...`
- `### Epic V8.5 — ...` → `### Epic V8.52 — ...`
- `### Epic V8.6 — ...` → `### Epic V8.53 — ...`
- `V8.1–V8.6` → `V8.48–V8.53`
- `M1 Epic V1.2` → unchanged

### m9.md (M9)
- `### Epic V9.1 — ...` → `### Epic V9.54 — ...`
- `### Epic V9.2 — ...` → `### Epic V9.55 — ...`
- `### Epic V9.3 — ...` → `### Epic V9.56 — ...`
- `### Epic V9.4 — ...` → `### Epic V9.57 — ...`
- `### Epic V9.5 — ...` → `### Epic V9.58 — ...`
- `### Epic V9.6 — ...` → `### Epic V9.59 — ...`
- `V9.1–V9.5` → `V9.54–V9.58`
- `V9.6` → `V9.59`

## Files to Update (Epics README.md)

`doc/strategy/roadmap/epics/README.md` — the main index table:

1. **Milestone 1 section** — links and IDs unchanged (V1.1–V1.5)
2. **Milestone 2 section** — all IDs and links:
   - `V2.1` → `V2.6`, `V2.2` → `V2.7`, ..., `V2.5` → `V2.10`
3. **Milestone 3 section** — all IDs and links:
   - `V3.6` → `V3.11`, ..., `V3.11` → `V3.16`
4. **Milestone 4 section** — all IDs and links:
   - `V4.12` → `V4.17`, ..., `V4.20` → `V4.25`
5. **Milestone 5 section** — all IDs and links:
   - `V5.21` → `V5.26`, ..., `V5.29` → `V5.34`
6. **Milestone 6 section** — all IDs and links:
   - `V6.1` → `V6.35`, ..., `V6.6` → `V6.40`
7. **Milestone 7 section** — **NOTE: DESCRIPTION IS SWAPPED** (see Pre-flight above)
   - Fix the milestone description from "Options and Derivatives" to "Portfolio Analytics"
   - `V7.1` → `V7.41`, ..., `V7.7` → `V7.47`
   - Fix descriptions to match actual epic content (BLAS/LAPACK, not QuantLib)
8. **Milestone 8 section** — **NOTE: DESCRIPTION IS SWAPPED** (see Pre-flight above)
   - Fix the milestone description from "Portfolio Analytics" to "Options and Derivatives" — actually wait, let me re-check: the README has M8 as "Portfolio Analytics" with BLAS/LAPACK descriptions, but M8's actual epics (V8.1–V8.6) are about Cuba/FFTW. So the README M7/M8 section titles and descriptions are swapped relative to both the milestone files AND the actual epic contents.
   - `V8.1` → `V8.48`, ..., `V8.6` → `V8.53`
   - Fix descriptions to match actual epic content (Cuba/FFTW, not BLAS/LAPACK)
9. **Milestone 9 section** — all IDs and links:
   - `V9.1` → `V9.54`, ..., `V9.6` → `V9.59`
10. **Dependency Evolution Matrix** — the milestone column headers M1–M9 remain the same, but any V references in the rationale text need updating (there don't appear to be any V references in the matrix itself)

**V8.7 issue:** The README lists `V8.7` as "Historical scenario analysis and backtesting" under Milestone 8. No corresponding file exists. Plan decision: remove V8.7 from the README table during the rename (or flag as pending/removed).

## Files to Update (Templates)

### `doc/strategy/templates/epic-template.md`
- Example IDs: `V1.6` → `V1.6` (unchanged, no V1.6 exists yet so it's just a placeholder example)
- Story breakdown example: `V5.1.S1` → `V5.26.S1` (if keeping the example) — or leave as-is since it's a template example
- The template uses V1.6 as an example of naming convention — leave unchanged since it's illustrative

### `doc/strategy/templates/milestone-template.md`
- Example: `V4.12` → `V4.17`, `V4.12.S2` → `V4.17.S2`, `V4.12.S2.T3` → `V4.17.S2.T3`
- Example: `V6.9` → `V6.40` (or keep as placeholder — it's an example of what to avoid)
- Example: `V6.31`, `V6.1`, `V6.2`, `V6.3`, `V6.4`, `V6.6`, `V6.7`, `V6.8`, `V6.9` — these are examples in the template. Decide: update or keep as illustrative.
  - **Recommendation: update.** If these are meant to be realistic examples, they should use the new numbering scheme.
  - `V6.31` → `V6.36`, `V6.1` → `V6.35`, `V6.2` → `V6.36` (conflict!) — these are just examples, not real epics. Leave template examples as-is or update selectively.

### `doc/strategy/templates/story-template.md`
- Example: `V1.6` → unchanged (placeholder)
- Example: `V1.6.S2` → unchanged
- Example: `V1.6.S2.T3` → unchanged

### `doc/strategy/templates/release-template.md`
- `V5.26 — Portfolio Guardrails` → `V5.31 — Portfolio Guardrails`
- `V6.6.S2 — Snapshot Review Surface` → `V6.40.S2 — Snapshot Review Surface`

## Files to Update (Other Markdown Files in doc/)

### `doc/strategy/roadmap/milestones/README.md`
- Line 14: `An "epic" here means a named roadmap increment such as \`V0.1\` or a` — no V references to update

### `doc/knowledge/architecture.md`
- Check for any Vx.y references — none found in initial search

### `doc/execution/telemetry.md`, `doc/execution/security.md`, `doc/execution/observability.md`
- Check for Vx.y references — none found in initial search

## Execution Order

### Phase 1: File Renames (no content changes yet)
Rename all epic files. Do NOT edit file content yet — only rename.

```bash
cd doc/strategy/roadmap/epics
# M2 renames
mv V2.1.md V2.6.md
mv V2.2.md V2.7.md
mv V2.3.md V2.8.md
mv V2.4.md V2.9.md
mv V2.5.md V2.10.md
# M3 renames
mv V3.6.md V3.11.md
mv V3.7.md V3.12.md
mv V3.8.md V3.13.md
mv V3.9.md V3.14.md
mv V3.10.md V3.15.md
mv V3.11.md V3.16.md
# M4 renames
mv V4.12.md V4.17.md
mv V4.13.md V4.18.md
mv V4.14.md V4.19.md
mv V4.15.md V4.20.md
mv V4.16.md V4.21.md
mv V4.17.md V4.22.md
mv V4.18.md V4.23.md
mv V4.19.md V4.24.md
mv V4.20.md V4.25.md
# M5 renames
mv V5.21.md V5.26.md
mv V5.22.md V5.27.md
mv V5.23.md V5.28.md
mv V5.24.md V5.29.md
mv V5.25.md V5.30.md
mv V5.26.md V5.31.md
mv V5.27.md V5.32.md
mv V5.28.md V5.33.md
mv V5.29.md V5.34.md
# M6 renames
mv V6.1.md V6.35.md
mv V6.2.md V6.36.md
mv V6.3.md V6.37.md
mv V6.4.md V6.38.md
mv V6.5.md V6.39.md
mv V6.6.md V6.40.md
# M7 renames
mv V7.1.md V7.41.md
mv V7.2.md V7.42.md
mv V7.3.md V7.43.md
mv V7.4.md V7.44.md
mv V7.5.md V7.45.md
mv V7.6.md V7.46.md
mv V7.7.md V7.47.md
# M8 renames
mv V8.1.md V8.48.md
mv V8.2.md V8.49.md
mv V8.3.md V8.50.md
mv V8.4.md V8.51.md
mv V8.5.md V8.52.md
mv V8.6.md V8.53.md
# M9 renames
mv V9.1.md V9.54.md
mv V9.2.md V9.55.md
mv V9.3.md V9.56.md
mv V9.4.md V9.57.md
mv V9.5.md V9.58.md
mv V9.6.md V9.59.md
```

### Phase 2: Update Epic File Content
For each renamed epic file, perform global find-and-replace of old Vx.y IDs to new Vx.y IDs. This must be done **after** renames to avoid renaming files mid-edit.

Use a script that applies all old→new mappings to each file:
- `V2.1` → `V2.6`, `V2.2` → `V2.7`, ..., `V2.5` → `V2.10`
- `V3.6` → `V3.11`, ..., `V3.11` → `V3.16`
- ... and so on for all milestones
- Also handle ranges: `V2.1–V2.5` → `V2.6–V2.10`, `V4.14–V4.15` → `V4.19–V4.20`, etc.
- Also handle story refs: `V2.1.S1` → `V2.6.S1`, `V4.14.S1–S3` → `V4.19.S1–S3`, etc.

**Critical:** The replacement must be done in order to avoid partial matches. E.g., replace `V4.17` before `V4.1` (if any existed), and replace `V4.20` before `V4.2` (if any). Since all old IDs are ≥ 2 digits after the dot, a single-pass replacement with all old→new mappings should work. But ranges and story refs add complexity.

**Recommended approach:** Write a Python script that:
1. Reads each renamed epic file
2. Applies all Vx.y → Vy.y replacements (using regex with word boundaries to avoid partial matches)
3. Handles ranges (Vx.y–Vx.z → Vy.y–Vy.z)
4. Handles story refs (Vx.y.Sn → Vy.y.Sn, Vx.y.Sn–Sm → Vy.y.Sn–Sm)
5. Updates the epic title line (`# VX.Y:` → `# VY.N:`)
6. Writes the file back

### Phase 3: Update Milestone Files
Update `m1.md` through `m9.md`:
- Epic header lines: `### Epic VX.Y — Title` → `### Epic VY.N — Title`
- Cross-reference text within descriptions
- Range references in text

### Phase 4: Update README and Templates
- `doc/strategy/roadmap/epics/README.md` — update all table entries
- `doc/strategy/templates/epic-template.md` — update examples
- `doc/strategy/templates/milestone-template.md` — update examples
- `doc/strategy/templates/release-template.md` — update examples
- `doc/strategy/templates/story-template.md` — update examples

### Phase 5: Verify
- Run `grep -r "V[0-9]\+\.[0-9]\+" doc/strategy/` to find any remaining old-style references
- Verify every epic file's title line matches its filename
- Verify every file referenced in a README link exists
- Verify no broken Vx.y references remain in milestone files
- Check the M7/M8 swap fix in the epics README

## Verification Script

After all changes, run:

```bash
cd doc/strategy/roadmap/epics

# 1. Every existing epic file should have title matching filename
for f in V*.md; do
    num=$(basename "$f" .md)
    title=$(grep '^# ' "$f" | head -1 | sed 's/^# //')
    if [ "$title" != "$num:" ] && [ "$title" != "$num:"* ]; then
        echo "MISMATCH: $f has title '$title'"
    fi
done

# 2. No old-style references should remain (except in templates/examples)
grep -rn 'V[0-9]\+\.[0-9]\+' . --include='*.md' | grep -v 'README.md' | grep -v 'V1\.' | grep -v 'V2\.[6-9]' | grep -v 'V2\.1[0-9]' | grep -v 'V3\.[1-6]' | ... # etc.
# Better: verify no old mapping is present
grep -rn 'V2\.1\b\|V2\.2\b\|V2\.3\b\|V2\.4\b\|V2\.5\b' . --include='*.md'
grep -rn 'V3\.6\b\|V3\.7\b\|V3\.8\b\|V3\.9\b' . --include='*.md'
# etc.

# 3. README links should resolve
for link in V*.md; do
    if [ ! -f "$link" ]; then
        echo "BROKEN LINK: $link in README"
    fi
done

# 4. Count total epics
ls V*.md | wc -l  # should be 59
```

## Risks and Edge Cases

1. **M7/M8 swap in epics README:** The table of contents in the README has M7 and M8 descriptions swapped. The actual epic files and milestone files are correct. During Phase 4, the README must be fixed.

2. **V8.7 phantom entry:** The README lists V8.7 but no file exists. Decide during execution whether to remove it from the README or note it as pending.

3. **Template examples:** Templates contain example IDs that may or may not need updating. Decide per template whether examples should be updated to match the new scheme.

4. **Cross-references in non-epic, non-milestone files:** The initial search found V references in `doc/strategy/templates/release-template.md`, `doc/strategy/templates/story-template.md`, and `doc/strategy/templates/milestone-template.md`. These are all template files.

5. **Git history:** After renaming, `git log --follow` will still trace the file history. Make sure to use `git mv` or commit renames properly.

6. **Story files:** No story files exist in the repo (no separate story markdown files). Story references are only within epic files and milestone files as `- [ ] VX.Y.SN: Title` bullets. These are updated in Phase 2.

7. **GitHub issue sync:** If any epics are linked to GitHub issues, the issue labels and sub-issue relationships will not auto-update. This is a manual process outside the scope of this rename plan.

## Summary of All Affected Paths

### Epic files (59 renames)
`doc/strategy/roadmap/epics/V2.1.md` → `V2.6.md`
`doc/strategy/roadmap/epics/V2.2.md` → `V2.7.md`
`doc/strategy/roadmap/epics/V2.3.md` → `V2.8.md`
`doc/strategy/roadmap/epics/V2.4.md` → `V2.9.md`
`doc/strategy/roadmap/epics/V2.5.md` → `V2.10.md`
`doc/strategy/roadmap/epics/V3.6.md` → `V3.11.md`
`doc/strategy/roadmap/epics/V3.7.md` → `V3.12.md`
`doc/strategy/roadmap/epics/V3.8.md` → `V3.13.md`
`doc/strategy/roadmap/epics/V3.9.md` → `V3.14.md`
`doc/strategy/roadmap/epics/V3.10.md` → `V3.15.md`
`doc/strategy/roadmap/epics/V3.11.md` → `V3.16.md`
`doc/strategy/roadmap/epics/V4.12.md` → `V4.17.md`
`doc/strategy/roadmap/epics/V4.13.md` → `V4.18.md`
`doc/strategy/roadmap/epics/V4.14.md` → `V4.19.md`
`doc/strategy/roadmap/epics/V4.15.md` → `V4.20.md`
`doc/strategy/roadmap/epics/V4.16.md` → `V4.21.md`
`doc/strategy/roadmap/epics/V4.17.md` → `V4.22.md`
`doc/strategy/roadmap/epics/V4.18.md` → `V4.23.md`
`doc/strategy/roadmap/epics/V4.19.md` → `V4.24.md`
`doc/strategy/roadmap/epics/V4.20.md` → `V4.25.md`
`doc/strategy/roadmap/epics/V5.21.md` → `V5.26.md`
`doc/strategy/roadmap/epics/V5.22.md` → `V5.27.md`
`doc/strategy/roadmap/epics/V5.23.md` → `V5.28.md`
`doc/strategy/roadmap/epics/V5.24.md` → `V5.29.md`
`doc/strategy/roadmap/epics/V5.25.md` → `V5.30.md`
`doc/strategy/roadmap/epics/V5.26.md` → `V5.31.md`
`doc/strategy/roadmap/epics/V5.27.md` → `V5.32.md`
`doc/strategy/roadmap/epics/V5.28.md` → `V5.33.md`
`doc/strategy/roadmap/epics/V5.29.md` → `V5.34.md`
`doc/strategy/roadmap/epics/V6.1.md` → `V6.35.md`
`doc/strategy/roadmap/epics/V6.2.md` → `V6.36.md`
`doc/strategy/roadmap/epics/V6.3.md` → `V6.37.md`
`doc/strategy/roadmap/epics/V6.4.md` → `V6.38.md`
`doc/strategy/roadmap/epics/V6.5.md` → `V6.39.md`
`doc/strategy/roadmap/epics/V6.6.md` → `V6.40.md`
`doc/strategy/roadmap/epics/V7.1.md` → `V7.41.md`
`doc/strategy/roadmap/epics/V7.2.md` → `V7.42.md`
`doc/strategy/roadmap/epics/V7.3.md` → `V7.43.md`
`doc/strategy/roadmap/epics/V7.4.md` → `V7.44.md`
`doc/strategy/roadmap/epics/V7.5.md` → `V7.45.md`
`doc/strategy/roadmap/epics/V7.6.md` → `V7.46.md`
`doc/strategy/roadmap/epics/V7.7.md` → `V7.47.md`
`doc/strategy/roadmap/epics/V8.1.md` → `V8.48.md`
`doc/strategy/roadmap/epics/V8.2.md` → `V8.49.md`
`doc/strategy/roadmap/epics/V8.3.md` → `V8.50.md`
`doc/strategy/roadmap/epics/V8.4.md` → `V8.51.md`
`doc/strategy/roadmap/epics/V8.5.md` → `V8.52.md`
`doc/strategy/roadmap/epics/V8.6.md` → `V8.53.md`
`doc/strategy/roadmap/epics/V9.1.md` → `V9.54.md`
`doc/strategy/roadmap/epics/V9.2.md` → `V9.55.md`
`doc/strategy/roadmap/epics/V9.3.md` → `V9.56.md`
`doc/strategy/roadmap/epics/V9.4.md` → `V9.57.md`
`doc/strategy/roadmap/epics/V9.5.md` → `V9.58.md`
`doc/strategy/roadmap/epics/V9.6.md` → `V9.59.md`

### Milestone files (9 content edits)
`doc/strategy/roadmap/milestones/m2.md` — update V2.1–V2.5 → V2.6–V2.10
`doc/strategy/roadmap/milestones/m3.md` — update V3.6–V3.11 → V3.11–V3.16
`doc/strategy/roadmap/milestones/m4.md` — update V4.12–V4.20 → V4.17–V4.25
`doc/strategy/roadmap/milestones/m5.md` — update V5.21–V5.29 → V5.26–V5.34
`doc/strategy/roadmap/milestones/m6.md` — update V6.1–V6.6 → V6.35–V6.40
`doc/strategy/roadmap/milestones/m7.md` — update V7.1–V7.7 → V7.41–V7.47
`doc/strategy/roadmap/milestones/m8.md` — update V8.1–V8.6 → V8.48–V8.53
`doc/strategy/roadmap/milestones/m9.md` — update V9.1–V9.6 → V9.54–V9.59

### README and templates (4 files)
`doc/strategy/roadmap/epics/README.md` — update all table entries, fix M7/M8 swap, remove V8.7
`doc/strategy/templates/epic-template.md` — update example IDs
`doc/strategy/templates/milestone-template.md` — update example IDs
`doc/strategy/templates/release-template.md` — update example IDs
