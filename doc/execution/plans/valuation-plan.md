# valuation_core — Architecture

**Reassessed:** 2026-10-01. Target: Zig. (Original target was Rust; language decision was
arbitrary and has been rolled back — see D1.) Methodology: `docs/prompt.md`. Data: `data/metadata/`.

**What this package is.** A deterministic engine that performs Damodaran intrinsic valuation,
driven by Damodaran's own published datasets, implementing every calculable step of
`docs/prompt.md`, such that `(inputs, policy, engine version)` reproduces a bit-identical result.

---

## 0. Governing principle

> **Code calculates everything that is calculable. The LLM supplies only sourced claims that cannot
> be calculated, and never produces a number that code could have produced.**

This is the single rule the architecture serves. Two consequences that are easy to get wrong:

- **Code never makes judgements it cannot ground.** It does not decide whether a company has a
  moat, which peers are comparable, or how a region decomposes into countries. Those are inputs.
- **But code always computes the evidence bearing on those judgements**, and audits the claim
  against it. The engine cannot know whether a moat will persist; it can and must compute the
  historical realized ROIC − WACC spread and flag an asserted spread that history does not support.

The division is not "hard things go to the LLM." It is: *claims* are inputs, *arithmetic* is code,
and every claim that touches a number gets checked against computed evidence.

---

## 1. The pivot

```zig
pub fn runValuation(
    gpa: std.mem.Allocator,
    inputs: *ValuationInputs,
    policy: *ValuationPolicy,
) AllocatorError!ValuationResult
```

Pure, cheap, side-effect free. The allocator is explicit — no hidden allocations in the hot path.
Everything downstream is a re-run: sensitivity ~15, scenarios 4, reverse DCF 100, Monte Carlo N.
Four analyses, one implementation.

---

## 2. Dataset → methodology mapping

The 26 files in `data/metadata/` are Damodaran's published tables. This is what each one feeds.
`us_*` applies to US-domiciled companies, `global_*` otherwise; selection is by company domicile and
is itself a deterministic policy, not a choice made per valuation.

### Cost of capital (Step 2)

| Dataset | Columns used | Feeds |
|---|---|---|
| `us_implied_erp.csv` | `T.Bond Rate`, `Implied ERP (FCFE)` | **USD risk-free rate** and the **mature-market ERP**. Both in one file, same vintage — which is the point: they are a matched pair and must not be sourced independently. |
| `global_risk_premiums.csv` | `Country`, `Moody's rating`, latest spread column | Country **default spreads** → CRP (see §3.1 — these are *not* CRP as published) |
| `rating_risk_premiums.csv` | `Rating`, latest default spread | Synthetic-rating cost of debt, tier 2–3 of the Step 2B ladder |
| `us_betas.csv` / `global_beta.csv` | `Unlevered beta`, `Unlevered beta corrected for cash`, `D/E Ratio`, `Effective Tax rate` | **Bottom-up beta** (Step 2A Option A). Use the cash-corrected unlevered beta, then relever at the subject company's own market D/E. |
| `global_tax_rates.csv` | `Corporate Tax Rate`, `Tax Rate Accounting for Global Minimum Tax` | **Marginal** tax rate for terminal convergence (A4). Use the Pillar Two adjusted rate where it binds. |
| `us_wacc.csv` / `global_wacc.csv` | `Cost of Capital`, `Cost of Equity`, `Cost of Debt`, `D/(D+E)` | Sanity benchmark for the computed WACC — an industry cross-check, never an input |

### Growth and reinvestment (Step 3)

| Dataset | Columns used | Feeds |
|---|---|---|
| `us_growth_EBIT.csv` / `global_growth_EBIT.csv` | `ROC`, `Reinvestment Rate`, `Expected Growth in EBIT` | Industry benchmark for the **fundamental growth equation**. This file literally publishes `g = ROC × Reinvestment Rate` by sector — the direct cross-check for a company's Stage 1 inputs. |
| `us_growth_revenue.csv` / `global_growth_revenue.csv` | `CAGR in Revenues- Last 5 years`, `Expected Growth in Revenues - Next 5 years` | Plausibility band for Stage 1 growth; consensus cross-check |
| `us_capex.csv` / `global_capex.csv` | `Net Cap Ex/ EBIT (1-t)`, `Sales/ Invested Capital (LTM)`, `Net R&D` | Reinvestment-rate benchmark; sales-to-capital alternative; **R&D capitalization** sector reference (A3) |
| `us_working_capital.csv` / `global_working_capital.csv` | `Non-cash WC/ Sales` | Working-capital intensity for the ΔWC component of reinvestment |
| `us_margin.csv` / `global_margin.csv` | `Pre-tax, Pre-stock compensation Operating Margin`, `Pre-tax Unadjusted Operating Margin`, `Pre-tax Lease adjusted Margin` | Target margin for base-year normalization. **Note these three columns directly corroborate A1 and A3**: Damodaran publishes margins both before and after SBC, and lease-adjusted — he treats both as adjustments that must be made explicit, which is exactly the position the amended methodology now takes. |
| `us_tax_rate.csv` / `global_industry_tax_rate.csv` | `Aggregate tax rate`, `Cash Taxes/Accrual Taxes` | Effective-rate sanity check against sector |

### Cross-checks (Steps 5B and 7)

| Dataset | Columns used | Feeds |
|---|---|---|
| `us_vebitda.csv` / `global_vebitda.csv` | `EV/EBITDA`, `EV/EBIT`, `EV/EBITDAR&D` | **Exit-multiple terminal value** (Step 5B); implied-multiple check (Step 7.1) |
| `us_pe.csv` / `global_pe.csv` | `Current PE`, `Trailing PE`, `Forward PE` | Implied terminal PE sanity check |
| `us_ps.csv` / `global_ps.csv` | `Price/Sales`, `EV/Sales` | Implied P/S check |

Note `EV/EBITDAR&D` exists precisely because Damodaran capitalizes R&D — using `EV/EBITDA` against
an R&D-adjusted EBITDA would be an apples-to-oranges comparison. The multiple chosen must match the
adjustment state of the metric.

---

## 3. Dataset integrity issues (found, must be handled at ingestion)

These are concrete and would each produce a silently wrong valuation.

### 3.1 `global_risk_premiums.csv` contains default spreads, not country risk premiums

This is the most dangerous one. The file's values are **sovereign default spreads**. Damodaran's
country risk premium is derived from them:

```
CRP(country) = default_spread(country) × (σ_country_equity_index / σ_country_bond)
```

The scaling factor is typically ~1.3–1.5 and is **not present in any file here**. Treating the CSV
values as CRP directly understates equity country risk by roughly a third.

*Decision:* the relative-volatility scalar is an explicit, sourced `ValuationPolicy` field with no
silent default. The loader's type is named `DefaultSpread`, not `Crp`, so the conversion cannot be
skipped by accident — it is a comptime type error to put a `DefaultSpread` where a `Crp` is required.

### 3.2 Unit mismatch between the two risk files

`rating_risk_premiums.csv` is in **basis points** (`A1,60,67`). `global_risk_premiums.csv` is in
**percent** (`Abu Dhabi,Aa2,0.60%,0.91%`). They are used together in the cost-of-debt ladder. A
`Rate` newtype with explicit `fromBps` / `fromPercent` constructors makes the mismatch
unrepresentable.

### 3.3 Column headers are dates, and there are two vintages

`global_risk_premiums.csv` has `12/31/2025` and `3/31/2026` columns; `rating_risk_premiums.csv` the
same. The loader must select by `as_of` policy, not by column position, and record which vintage was
used in provenance.

### 3.4 Shape irregularities

- `us_wacc.csv` opens with a preamble block (`Long Term Treasury bond rate =,,,3.95%`), not a header
  row — a different shape from `global_wacc.csv`, which is a clean table.
- `us_vebitda.csv` and `global_vebitda.csv` repeat column names (`EV/EBITDA` twice: all firms vs
  money-making firms only). Positional disambiguation is required.
- `global_risk_premiums.csv` has an empty column 6 and a duplicated side table in columns 7–8.
- `us_implied_erp.csv` has footer rows with a blank first column (`,2016-2025,5.00%,7.84%`) mixed
  into the year series.

*Decision (D18):* none of these files is parsed at runtime. A build-time step normalizes each to a
typed internal form and emits a manifest of `{file, sha256, as_of, source_url, row_count}`. Raw
spreadsheet exports never reach the engine.

### 3.5 Industry classification is the join key and has no standard

Every industry table joins on `Industry Name` — Damodaran's own ~95-sector scheme, which maps to no
public standard (not GICS, not SIC, not NAICS). A company must be assigned to a Damodaran sector,
and that assignment is a **sourced input**, not something code derives. Persist it per company;
never let it be re-guessed per run, or the bottom-up beta silently changes between valuations.

---

## 4. Two questions resolved

### 4.1 CRP exposure basis

**The issue.** The weighted CRP is `Σ (exposure weight × CRP)`. The question is what measures
*exposure*. The methodology says revenue share. Revenue share is a proxy, and it misstates risk in
three recognised ways:

1. **Revenue location ≠ risk location.** A company invoicing from Switzerland while its factories
   are in Turkey books Swiss revenue and carries Turkish risk. The reverse also happens: 30% of
   revenue from Brazil with every asset in Germany is a smaller exposure than the revenue share
   implies.
2. **The disclosure itself is inconsistent.** Geographic revenue in filings is variously reported
   by customer domicile, shipping destination, or selling-subsidiary domicile. The same company can
   yield materially different "geographic splits" depending on which table you read.
3. **Damodaran's own refinement is lambda (λ).** He weights by *relative* exposure rather than raw
   revenue share: `λ = (company's % revenue from country) / (average company in that country's %
   revenue from there)`, with contribution `λ × CRP`. A company earning 30% in Brazil where the
   average Brazilian firm earns 70% there has λ ≈ 0.43 — under-proportionate exposure.

**Decision: revenue-weighted.** Not because it is theoretically best, but because it is the only
basis `data/metadata/` supports. Lambda needs average revenue concentration by country, which no
file here carries; the returns-based lambda needs price history, which we also do not have. Choosing
a basis we cannot compute would push the number back to the LLM, violating §0. The basis used is
recorded in the output, and if the lambda inputs are ever added it becomes a policy switch rather
than a rewrite.

**What stays an input.** Code cannot know revenue by country — nobody can hand it the invoices.
So exposure is supplied against a **fixed block taxonomy** coarse enough that companies actually
disclose at that granularity. See §4.3.

### 4.3 Geographic exposure

Geographic exposure is an **input**. Code cannot know revenue by country, so it does not try. The
design question is only what shape that input takes.

```zig
pub const GeoExposure = struct {
    weights: GeoWeights,   // must sum to 1.0
    basis: ExposureBasis,  // Revenue | Assets | Production
    source: SourceId,      // which disclosure it came from
    as_of: Date,
};

pub const GeoWeights = std.StaticStringMap(Weight); // or sorted array of (GeoRegion, Weight)
```

```zig
pub const GeoRegion = union(enum) {
    country: std.iso_3166_1.Alpha3,  // preferred: no approximation
    block: GeoBlock,                 // when the filing discloses only regionally
    composite: []const GeoBlock,     // "EMEA", "APLA" — one disclosed number, several blocks
};

pub const GeoBlock = enum {
    north_america,
    latin_america,
    europe,
    middle_east_africa,
    greater_china,
    japan,
    india,
    asia_pacific_other,
    unallocated,
};
```

#### Block definitions

The taxonomy is the **union of how large multinationals actually disclose geography**. The binding
constraint is that a filing's segment note must map onto it without the caller inventing a split.
Analytically tidier groupings — splitting Southern from Western Europe, or carving out distressed
sovereigns — were rejected because no company reports at that granularity, so the input could never
be filled from a real filing.

| Block | Members |
|---|---|
| `north_america` | United States, Canada |
| `latin_america` | Mexico, Central and South America, Caribbean |
| `europe` | All of Europe, developed and emerging, including the UK, Türkiye and Russia |
| `middle_east_africa` | Gulf states, rest of the Middle East, North Africa, Sub-Saharan Africa |
| `greater_china` | Mainland China, Hong Kong, Macau, Taiwan |
| `japan` | Japan |
| `india` | India |
| `asia_pacific_other` | Korea, Australia, New Zealand, Singapore, ASEAN, rest of Asia-Pacific |
| `unallocated` | Residual the filing does not break out |

#### Mapped against real disclosure

| Company | Reported segments | Maps to |
|---|---|---|
| **Apple** | Americas; Europe; Greater China; Japan; Rest of Asia Pacific | `north_america`+`latin_america`; `europe`+`middle_east_africa`+`india`; `greater_china`; `japan`; `asia_pacific_other` |
| **Nike** | North America; EMEA; Greater China; APLA | `north_america`; `europe`+`middle_east_africa`; `greater_china`; `asia_pacific_other`+`latin_america` |
| **Nvidia** | United States; Taiwan; China; Singapore; Other | `north_america`; `greater_china`; `greater_china`; `asia_pacific_other`; `unallocated` |
| **Stellantis** | North America; Enlarged Europe; South America; Middle East & Africa; China, India & Asia Pacific | `north_america`; `europe`; `latin_america`; `middle_east_africa`; `greater_china`+`india`+`asia_pacific_other` |
| **GE** | US; Europe; Asia; Americas (non-US); Middle East & Africa | `north_america`; `europe`; `asia_pacific_other`+`greater_china`; `latin_america`; `middle_east_africa` |

Note what this exercise shows: **filings routinely bundle more coarsely than any sensible block
set.** Apple's "Europe" includes India and Africa. Nike's "APLA" spans Asia-Pacific and Latin
America. Those are single reported numbers, and forcing the caller to split them would mean
inventing weights — the exact failure this design forbids. So the input admits composite regions:

A composite's premium is taken over the union of its member countries, so "EMEA 30%" is usable
directly from the filing with no fabricated decomposition.

#### Membership is reference data, not a judgement

The membership table is a fixed list maintained in the repository alongside the datasets, versioned
with them, and covered by the dataset manifest hash. It is not re-derived per valuation, and the
model is never asked to assign a country to a block.

#### The trade this makes

Blocks this coarse are not credit-homogeneous — `europe` spans Germany to Greece, and
`middle_east_africa` spans Qatar to Zimbabwe. That imprecision is accepted because the alternative is
an input nobody can fill. The engine therefore **reports each block's internal dispersion alongside
its premium** rather than engineering it away, so a reader can see when a coarse bucket is carrying
a lot of uncertainty. Country-level weights remain the preferred path whenever a filing provides
them.

#### Derivation (engine side)

```
CRP(country) = max(0, rating_spread(rating(country)) - rating_spread(base_market))
               x relative_equity_volatility
CRP(block)   = median over member countries
weighted_CRP = Σ (weight × CRP)
```

`rating` and `rating_spread` are pure lookups into `global_risk_premiums.csv` and
`rating_risk_premiums.csv`. `relative_equity_volatility` is a sourced policy input with no default
(§3.1).

A block's CRP is the **median of its member countries** — no GDP or market-cap weighting, because
`data/metadata/` contains no such weights and importing them would put numbers into the engine that
do not come from the data. Block membership is the only reference data required, and it is a fixed
list.

#### Base-market netting

CRP is risk *above* a mature market, and the mature-market ERP already embeds the base market's own
risk. Subtract the base market's spread; its CRP is zero by construction.

**Never assume the base market is Aaa.** Read its rating from the data like any other country.
Hardcoding a zero base silently inflates every country's premium the moment the base market is
downgraded.

## 5. Module architecture

Module layout makes purity structural rather than conventional: `valuation_core` is compiled with
no `std.Io` imports and no file access, so it cannot.

```
src/
  valuation_core/     pure. Money<C>, DataPoint<T>, Period, Rate, ValuationPolicy,
                      metrics, adjustments, dilution, capital, growth,
                      projection, terminal, bridge, reverse_dcf, sensitivity,
                      scenarios, montecarlo
  valuation_data/     build-time dataset normalization, typed loaders, XBRL mapping
  valuation_io/       source resolution, FX snapshots, provenance capture
  valuation_audit/    the Step 10 checks
  valuation_report/   result assembly, Step 11 table, rendering
  valuation_cli/      JSON in / JSON out
  valuation_mcp/      stdio MCP server
datasets/
  manifest.toml       per-file sha256, as_of, source_url
  normalized/         build-time output
```

### Methodology step → module → datasets

| `prompt.md` step | Module | Datasets |
|---|---|---|
| 1A Market data | `io.market` | — |
| 1B–1D Statements | `data.xbrl`, `core.metrics` | — |
| 1 Accounting adjustments (R&D, leases) | `core.adjustments` | `*_capex` (Net R&D), `*_margin` (lease-adjusted) |
| 1 Base-year normalization | `core.metrics.normalize` | `*_margin` |
| 1E History | `core.metrics.history` | — |
| 1F Consensus | `io.consensus` | `*_growth_revenue` |
| 1G Transcripts | **LLM** → structured evidence | — |
| 2A Beta | `core.capital.beta` | `us_betas`, `global_beta` |
| 2A CRP | `core.capital.crp` | `global_risk_premiums` + policy σ scalar |
| 2A Ke | `core.capital.cost_of_equity` | `us_implied_erp` |
| 2B Kd | `core.capital.cost_of_debt` | `rating_risk_premiums` |
| 2C–2D WACC | `core.capital.wacc` | `*_wacc` (benchmark only) |
| 3A Historical ROIC/reinvestment | `core.growth.history` | `*_growth_EBIT` |
| 3B Three stages | `core.growth.stages` | `*_growth_EBIT`, `*_capex`, `*_working_capital` |
| 3B Tax convergence | `core.growth.tax_path` | `global_tax_rates` |
| 4 Projection | `core.projection` | — |
| 5A Gordon TV | `core.terminal.gordon` | — |
| 5B Exit multiple | `core.terminal.exit_multiple` | `*_vebitda` |
| 6 FX | `core.fx`, `io.fx` | — |
| 6B Equity bridge | `core.bridge` | — |
| 6 Option valuation | `core.dilution.options` | — |
| 7.1 Implied multiples | `crosschecks.multiples` | `*_pe`, `*_ps`, `*_vebitda` |
| 7.2 Reverse DCF | `core.reverse_dcf` | — |
| 7.3 Peer comps | `crosschecks.peers` | peer set = sourced input |
| 8A–8C Sensitivity, scenarios, MC | `core.sensitivity`, `::scenarios`, `::montecarlo` | — |
| 9 Conclusion | `report` | — |
| 10 Self-audit | `audit` | — |
| 11 Transparency | `report.sources` | manifest |

Only step 1G and the three sourced inputs (Damodaran sector, peer set, moat spread) are not code.

---

## 6. Decisions register

| # | Decision | Rationale in one line |
|---|---|---|
| D1 | **Zig**, not Rust (reversal of the original D1) | The original architecture was written against Rust, with an arbitrary language decision in D1 selecting Rust over alternatives. That decision was revisited and reversed — Zig was chosen instead. Rationale: `Money<C>` via comptime struct parameter (Zig does not need traits/impl for phantom typing); `std.json`/`std.csv`/`std.testing` mature and stable; Zig 0.17 has stable ABI for FFI, no minor-version breaking changes. Rust's `serde` + `csv` + `proptest` are also mature, so the original Rust pick was defensible but unreasoned. Zig's comptime system avoids the trait-object overhead for phantom-typed `Money<C>` and the `!Error` union-return convention maps cleanly to the `Result` → `!Error` shift. **Migration from Rust-targeted original:** all code sketches in the prior version used Rust syntax and idioms (`pub fn`, `Result<T, E>`, `BTreeMap`, `std::collections`). These have been replaced with Zig equivalents: `pub fn` stays, `Result<T, E>` → `ErrorUnion` (`T!Error`), `BTreeMap` → sorted arrays or `std.StaticStringMap` (comptime key types), `pub struct` → `pub const ... = struct {}`, `pub enum` → `pub const ... = enum {}`, `impl` blocks → free functions taking `*Self`, `Option<T>` → `?T`, `Result<T, E>` → `ErrorUnion`, `serde::Deserialize/Serialize` → `std.json` parse/write, `proptest` → `std.testing` + hand-written property tests. No logic changed — only language surface. |
| D2 | `f64` in the engine; exact decimal only at ingestion and rendering | A DCF is not a ledger; every industry platform models in binary64 |
| D3 | **Never `std.math.pow` for discount factors** — iterate multiplication | `std.math.pow` is not correctly rounded and varies by platform; repeated multiplication is bit-identical everywhere |
| D3b | No fast-math/FMA contraction; fixed summation order; no hash-map iteration in numeric paths | removes remaining sources of cross-machine drift |
| D4 | Phantom-typed `Money<C>` via comptime struct parameter; dynamic `AnyMoney` only at the edge | currency mixing becomes a compile error |
| D5 | ISO 10383 MIC, ISO 4217, RFC 3339, LEI, FIGI; ticker is a display key | replaces three incompatible ad-hoc conventions |
| D6 | Normalize statements to XBRL US-GAAP/IFRS element names | filings are already tagged; makes source priority meaningful |
| D7 | `provenance_hash = BLAKE3(canonical(inputs) ‖ policy ‖ semver ‖ dataset manifest)` | machine-checkable reproducibility; golden tests assert on it |
| D8 | Module layout; `valuation_core` imports no I/O module | purity is structural, not conventional |
| D9 | **SBC expensed, options valued separately, divide by shares outstanding** | adding SBC back treats a recurring real expense as free; treasury method ignores option time value |
| D10 | Effective tax rate years 1–5 → marginal by year 10 | effective rates reflect timing differences that do not persist in perpetuity |
| D11 | End-of-period discounting default; mid-period available, always stated | worth 4–5% of value; cannot be implicit |
| D12 | **Value in reporting currency, translate once at spot** | fixes a genuine inconsistency; one FX observation, not a forward curve |
| D13 | R&D capitalized by default, sector-dependent life | Damodaran's signature adjustment; was entirely absent |
| D14 | Invested capital includes goodwill; report both | excluding it flatters ROIC on acquisitive firms |
| D15 | `!Error` everywhere; no `unreachable` in library code | reporting an unusable input beats aborting |
| D16 | Golden + property-based + `std.testing` invariant checks | properties catch what examples miss |
| D17 | Audit checks carry severity; any `Error` blocks rendering a conclusion | converts an instruction into a property |
| D18 | Datasets normalized and checksummed at build time | see §3 — raw exports are a reproducibility hazard |
| D19 | Core library + CLI binary + MCP server | language-agnostic boundary, trivially testable |
| D20 | Fixed-count bisection (100), not Brent | monotone in `g_high`; fixed count cannot vary by platform |
| D21 | Counter-based PRNG (Philox/ChaCha), seed in policy | parallelism and determinism otherwise mutually exclusive |
| D22 | **CRP basis: revenue-weighted** over a fixed 13-block taxonomy; `DefaultSpread` and `Crp` are distinct comptime types | §4.1/§4.3 — only basis the data supports; §3.1 — conversion cannot be skipped |
| D22b | Block CRP = **median of member-country CRPs from the ratings data**; no GDP or other weighting | §4.3 — no weighting data exists in `data/metadata/`; inventing it would import numbers from outside the data |
| D22c | Geographic exposure is a **required input** (`GeoExposure`), country or block, never inferred | §4.3 — code cannot know revenue by country; absent input is a missing-input error like any other |
| D23 | **`moat_spread` is a sourced input, default 0.0**; code computes the evidence | §4.2 — code never decides moat, always computes realized spread |
| D24 | Damodaran sector assignment and peer set are persisted sourced inputs | re-guessing changes the bottom-up beta between runs |

---

## 7. Audit checks (Step 10)

| ID | Severity | Assertion |
|---|---|---|
| `TERMINAL_G_LE_RF` | Error | `g_stable ≤ risk_free_rate` of the forecast currency |
| `WACC_G_SPREAD` | Error | `WACC − g_stable ≥ 100bp` |
| `CURRENCY_CONSISTENT` | Error | cash flows, rf and WACC share one currency; `<CUR>` used exactly once |
| `FX_DATE_SINGLE` | Error | one FX date across translation, price and output |
| `FX_METHOD_NOT_MIXED` | Error | translate-at-end and translate-flows never combined |
| `SBC_TREATMENT` | Error | SBC not added back; option deduction and diluted-share divisor never both applied |
| `GROWTH_REINVEST_IDENTITY` | Error | `g(t) = ROIC(t) × reinv_rate(t)` every year |
| `ROIC_PATH_CONTINUOUS` | Error | no jump at the stage-2/terminal boundary |
| `BASE_YEAR_GROUNDED` | Error | stage-1 inputs derive from history, not assertion |
| `CAPITALIZATION_CONSISTENT` | Error | leases and R&D each applied to EBIT, invested capital and ROIC together |
| `CRP_IS_NOT_SPREAD` | Error | CRP derived via the volatility scalar, not read raw from the spread table |
| `CRP_BASE_NETTED` | Error | base market's own CRP is exactly 0 (US is Aa1, not Aaa — see §4.3) |
| `GEO_COVERAGE` | Warn | `unallocated` block ≤ 10% of revenue |
| `GEO_EXPOSURE_VALID` | Error | `GeoExposure` supplied and its weights sum to 1.0 |
| `GEO_BLOCK_DISPERSION` | Warn | internal dispersion of each used block or composite is reported alongside its premium |
| `NO_INVENTED_INPUTS` | Error | every numeric input traces to a dataset file or the company filing |
| `FCFF_RECONCILES` | Warn | statement-derived vs normative FCFF within 2% of NOPAT |
| `TV_SHARE` | Warn | terminal value < 75% of operating asset value |
| `TERMINAL_METHOD_AGREEMENT` | Warn | Gordon vs exit multiple within 20% |
| `MOAT_SPREAD_SUPPORTED` | Warn | asserted moat spread ≤ realized historical mean `ROIC − WACC` |
| `MULTIPLE_MATCHES_ADJUSTMENT` | Warn | `EV/EBITDA` vs `EV/EBITDAR&D` matches the R&D adjustment state |
| `BASE_YEAR_NORMALIZED` | Warn | base margin within 30% of 5-year median, or normalized |
| `WACC_VS_INDUSTRY` | Warn | computed WACC within a band of the sector benchmark |
| `TAX_CONVERGENCE` | Info | terminal tax rate is marginal, not effective |
| `DISCOUNT_CONVENTION` | Info | convention stated |
| `SOURCE_COVERAGE` | Warn | every Step 11 input has source and `as_of` |
| `DATASET_VINTAGE` | Info | which dataset snapshot was used |

---

## 8. Phases

**Phase 0 — Methodology.** ✅ Complete. Round 1 fixed 11 internal inconsistencies; round 2 applied
A1–A7 (SBC, FX, R&D, tax convergence, discounting convention, goodwill, bisection). `prompt.md` is
now 1129 lines and contains no formula admitting two numerically different readings.

**Phase 1 — Foundations.** Zig workspace via `build.zig` (single build file, modules registered
with `b.addModule`/`b.createModule`). `Money<C>` comptime phantom type via struct, `Rate` (with
`fromBps`/`fromPercent`), `DataPoint<T>`, `Period`, `ValuationPolicy`, error enum, D3 lint set,
cross-platform bit-identity test. *Done when a currency mix fails to compile in a test expected to
fail to compile.*

**Phase 2 — Data.** Build-time normalization of all 26 datasets with the §3 irregularities handled
explicitly; manifest; typed loaders; `DefaultSpread`/`Crp` separation; XBRL mapping; statement
parsing; TTM; source-priority resolution. *Done when every number the engine needs carries
provenance.*

**Phase 3 — Core.** Metrics → history → R&D and lease capitalization → option valuation →
beta/CRP/Ke/Kd/WACC → growth stages with continuous ROIC and tax convergence → projection →
terminal → bridge → `runValuation`. *Done when no constant in the workspace is a valuation output.*

**Phase 4 — Derived analyses.** Sensitivity, scenarios, reverse DCF, exit multiple, implied
multiples, seeded Monte Carlo. All re-runs. *Done when every number in Steps 7–8 is code-produced.*

**Phase 5 — Audit and report.** §7 checks with severity; Step 11 table from provenance; the D17
refusal path.

**Phase 6 — Edges.** CLI, MCP server, agent contracts carrying "render, do not compute."

---

## 9. Remaining risks

1. **Damodaran sector assignment** has no algorithmic source (§3.5). It must be curated per company
   and persisted, or bottom-up betas drift between runs.
2. **Dataset refresh.** `data/metadata/` is a snapshot with mixed vintages (12/31/2025 and
   3/31/2026 columns in the same file). Refresh cadence and whether a refresh re-dates or
   invalidates stored valuations is undecided.
3. **Option-level data availability.** D9's primary route needs strike, expiry and volatility per
   grant tranche. Where filings disclose only aggregates, the documented treasury-method fallback
   applies and confidence drops — this will be common.
4. **`docs/` is untracked** and `mcp_server/`/`agents/` are deleted in the working tree while
   `pyproject.toml` still lists `mcp_server`. The Python tree is being replaced regardless, but the
   methodology documents have no committed baseline.
