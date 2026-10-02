# valuation_core — Architecture

**Language-agnostic specification.** Describes what the valuation package does, what it receives,
what it decides, and how. Notation is pseudo-schema, not any one language. Implementation language
and tooling choices live in `plan.md`; the methodology it implements lives in `prompt.md`.

---

## 1. Purpose

A deterministic engine that performs Damodaran intrinsic valuation. It takes normalized company
data plus Damodaran's published reference datasets and produces a valuation, a set of cross-checks,
and a machine-readable audit.

**Operating principle.** The engine calculates everything calculable. Anything it cannot calculate
arrives as a sourced input. It never fills a gap with a guess, and it never asks a language model to
supply a number that arithmetic could produce.

Three consequences:

- Geographic revenue, sector classification, peer sets and moat claims are **inputs**. The engine
  cannot derive them from statements.
- Every premium, rate, growth path and value **is** derived, from inputs and reference data only.
- Where an input is missing, the engine reports the gap and what it costs. It does not substitute a
  default that would look like an answer.

---

## 2. Pipeline

Seven stages. Each is a pure transformation of the previous one; nothing reaches back.

```
  ingest ──► resolve ──► adjust ──► derive ──► project ──► analyse ──► audit
```

| Stage | Responsibility | May perform I/O |
|---|---|---|
| **ingest** | parse filings and reference datasets into typed records | yes |
| **resolve** | pick one value per field from competing sources; build periods | no |
| **adjust** | capitalize R&D and leases; normalize a distorted base year | no |
| **derive** | historical metrics, dilution, cost of capital, growth paths | no |
| **project** | cash flow projection, terminal value, equity bridge | no |
| **analyse** | sensitivity, scenarios, reverse DCF, cross-checks, simulation | no |
| **audit** | evaluate every methodology rule; assign severities | no |

Only **ingest** touches the outside world. Stages 2–7 form one pure function:

```
run_valuation(inputs: ValuationInputs, policy: ValuationPolicy) → ValuationResult | Error
```

This function must be cheap and side-effect free, because the **analyse** stage calls it repeatedly:
roughly fifteen times for a sensitivity grid, four for scenarios, a hundred for a reverse-DCF solve,
and once per Monte Carlo iteration. Four analyses, one implementation. An engine whose core cannot
be re-entered has to implement each of them separately, and they will drift.

---

## 3. Inputs

Three things enter: **company inputs** (what we learned about this company), **reference data**
(Damodaran's datasets), and **policy** (how to decide). Policy and reference data are stable across
companies; only the first varies per valuation.

### 3.1 Provenance wrapper

Every externally-sourced scalar is wrapped. Bare numbers do not enter the engine.

```
DataPoint<T>
  value       : T
  source      : SourceId          # document, dataset, or provider
  source_type : Enum{ Filing, ProvidedStatement, CalculatedMetric,
                      EarningsReport, AnalystConsensus, ExternalDatabase }
  as_of       : Date
  period      : Optional<Period>
  currency    : Optional<Currency>
  confidence  : Enum{ High, Medium, Low }
```

This exists so the transparency table at the end of a valuation is generated rather than written,
and so source priority (§5.1) is mechanical rather than editorial.

### 3.2 Company inputs

```
ValuationInputs
  identity
    ticker          : String                 # display key only, never a primary key
    venue           : MicCode                # ISO 10383, e.g. XNAS
    legal_entity    : Optional<Lei>          # ISO 17442
    instrument      : Optional<Figi|Isin>
    domicile        : CountryCode            # ISO 3166
    reporting_ccy   : Currency               # ISO 4217

  sector            : DamodaranSector        # SOURCED INPUT — see §5.2

  statements        : List<FinancialPeriod>  # ≥5 annual periods for history
  market            : MarketData
  equity_claims     : EquityClaims
  geo_exposure      : GeoExposure            # SOURCED INPUT — see §5.8
  consensus         : Optional<List<ConsensusPeriod>>
  peers             : Optional<List<PeerCompany>>   # SOURCED INPUT
  qualitative       : Optional<List<QualitativeClaim>>
  fx                : Optional<FxSnapshot>
```

```
FinancialPeriod
  period            : Period                 # { kind: FY|Q|TTM, end: Date, fiscal_year: Int }
  currency          : Currency
  elements          : Map<XbrlElement, DataPoint<Money>>
```

Statement line items are keyed by **XBRL element name** (`Revenues`, `OperatingIncomeLoss`,
`ShareBasedCompensation`, `Goodwill`, …) rather than invented field names. Filings are already
tagged this way, so competing sources become competing values for the *same* element, which is what
makes source resolution well-defined.

```
MarketData
  price             : DataPoint<Money>
  price_date        : Date
  shares_outstanding: DataPoint<Decimal>
  market_cap        : DataPoint<Money>
  beta_regression   : Optional<RegressionBeta>   # { beta, r_squared, n_obs, window, frequency }

EquityClaims
  options    : List<{ count, strike: Money, remaining_life: Years }>
  rsus       : List<{ count, vested: Bool }>
  converts   : List<{ principal: Money, conversion_price: Money }>
  implied_vol: Optional<Rate>                    # required for fair-value route

GeoExposure
  weights : Map<GeoRegion, Weight>               # must sum to 1
  basis   : Enum{ Revenue, Assets, Production }
  source  : SourceId
  as_of   : Date

GeoRegion = Country(CountryCode)
          | Block(GeoBlock)
          | Composite(Set<GeoBlock>)             # one disclosed number, several blocks

GeoBlock = NorthAmerica | LatinAmerica | Europe | MiddleEastAfrica
         | GreaterChina | Japan | India | AsiaPacificOther | Unallocated

QualitativeClaim                                  # from transcripts; never a financial history source
  kind    : Enum{ Fact, Guidance, Opinion }
  metric  : String
  period  : Period
  low     : Optional<Decimal>
  high    : Optional<Decimal>
  quote   : String
  source  : SourceId
```

Qualitative claims are compared against the engine's own computed figures. They never replace them.

### 3.3 Reference data

Damodaran's published tables, normalized at build time into typed form with a manifest recording
each file's checksum, vintage date and source. Raw spreadsheet exports never reach the engine —
they carry preamble rows, footer rows, duplicate column names, blank spacer columns and mixed units,
all of which are reproducibility hazards if parsed at valuation time.

| Reference table | Supplies |
|---|---|
| implied ERP history | risk-free rate and mature-market equity risk premium, as a matched pair |
| country ratings and spreads | sovereign default spreads by country |
| rating → spread map | default spread by credit rating |
| unlevered betas by sector | bottom-up beta inputs |
| country tax rates | marginal statutory rates, including global-minimum adjustments |
| sector fundamental growth | benchmark ROIC, reinvestment rate, implied growth |
| sector reinvestment and working capital | reinvestment and ΔWC benchmarks |
| sector margins | margin benchmarks, including pre-SBC and lease-adjusted variants |
| sector multiples | EV/EBITDA, EV/EBIT, P/E, P/S for cross-checks and exit multiples |
| sector cost of capital | WACC benchmark for sanity checking only, never an input |

Two cautions that the type system should enforce rather than document:

- The country table contains **default spreads, not country risk premia**. Conversion requires a
  relative-equity-volatility scalar that is in none of the tables. Give default spreads and country
  risk premia distinct types so the conversion cannot be skipped by accident.
- The rating table and the country table use **different units** (basis points versus percent) and
  are used together. Construct rates through explicit `from_basis_points` / `from_percent`
  constructors so a unit error cannot be written.

### 3.4 Policy

Every discretionary choice in one place, so that two runs differing only in policy are comparable
and a run's behaviour is fully described by its policy record.

```
ValuationPolicy
  # cost of capital
  relative_equity_volatility : Rate            # required, no default (see §3.3)
  beta_method                : Enum{ PreferBottomUp, ForceRegression }
  base_market                : CountryCode     # whose ERP is the mature-market baseline

  # history
  history_years              : Int = 5
  roic_window                : Int = 3
  roic_statistic             : Enum{ Median, Mean }

  # growth
  high_growth_cap            : Rate = 0.25
  stage1_years               : Int = 5
  transition_years           : Int = 5
  moat_spread                : Rate = 0        # sourced input when non-zero
  stable_growth_rule         : Enum{ MinOfRiskFreeAndMacro, Explicit }

  # adjustments
  capitalize_rnd             : Bool = true
  rnd_amortization_years     : Map<DamodaranSector, Int>
  capitalize_leases          : Bool = true
  include_goodwill_in_ic     : Bool = true

  # mechanics
  discount_timing            : Enum{ EndOfPeriod, MidPeriod } = EndOfPeriod
  fx_method                  : Enum{ TranslateAtEnd, TranslateFlows } = TranslateAtEnd
  sbc_treatment              : Enum{ FairValueOptions, TreasuryMethodFallback }
  tax_convergence            : Enum{ EffectiveToMarginal, HoldEffective }

  # solver and simulation
  solver_iterations          : Int = 100
  monte_carlo_iterations     : Int
  monte_carlo_seed           : Int

  # datasets
  dataset_snapshot           : SnapshotId
```

---

## 4. Outputs

```
ValuationResult
  provenance_hash   : Hash               # see §6
  forecast_currency : Currency
  output_currency   : Currency

  history           : List<HistoricalYear>
  cost_of_capital   : CostOfCapital      # components, each with its source
  growth_path       : List<YearAssumptions>
  projection        : List<ProjectedYear>
  terminal          : TerminalValue       # both methods, and their divergence
  bridge            : EquityBridge        # every line item
  per_share         : Money
  reverse_dcf       : ImpliedGrowth
  sensitivity       : Matrix<Rate, Rate, Money>
  scenarios         : List<ScenarioOutcome>
  cross_checks      : List<CrossCheck>
  simulation        : Optional<Distribution>
  sources           : List<SourceRow>    # generated from DataPoint provenance

AuditResult
  checks  : List<{ id, severity, status, actual, limit, message }>
  verdict : Enum{ Clean, Warnings, Blocked }
```

Rendering layers must not recompute anything. Rows arrive complete, including intermediate columns
such as per-year reinvestment and discount factors, so that a report is a formatting pass.

`Blocked` means at least one check of severity `Error` failed. A blocked result may be inspected but
must not be rendered as an investment conclusion.

---

## 5. Decision rules

This section is the substance of the engine. Every rule below is deterministic: same inputs, same
choice, with explicit tie-breaks. Where the methodology permitted discretion, that discretion has
been converted into either a policy field or a fixed algorithm.

### 5.1 Which value to use when sources disagree

Ordered priority. First available wins:

1. Company filing
2. Provided financial statement
3. Provided calculated metric
4. Earnings report
5. Analyst consensus
6. External database

The resolver returns the selected value, the rejected alternatives, and the reason — not just the
winner. Two additional rules:

- **Conflict.** If a lower-priority source disagrees with the winner by more than a tolerance, the
  disagreement is recorded and surfaced. It does not change the selection.
- **Staleness.** A candidate older than a threshold relative to the valuation date is demoted below
  fresher candidates of lower nominal priority.

### 5.2 Which reference tables to read

Sector-level tables exist in US and global variants. Selection is by **company domicile**, not by
listing venue. The sector key is the Damodaran classification, which maps to no public standard and
therefore arrives as a sourced input, persisted per company. It is never re-derived, because
re-deriving it would silently change the bottom-up beta between runs of the same company.

### 5.3 Which period is the base year

1. Prefer a trailing-twelve-month period assembled from the four most recent quarters.
2. If quarterly data is incomplete, use the most recent complete fiscal year.
3. A period is complete only if every element required by the projection is present.
4. History requires `history_years` consecutive annual periods; fewer reduces confidence and is
   reported.

### 5.4 Whether the base year is usable as-is

The base year drives every projected cash flow, so it is tested before use:

1. Compute base operating margin and base return on invested capital.
2. Compare each against its median over the history window.
3. The base year is **distorted** if operating income is negative, or margin deviates from the
   median by more than 30% in relative terms.
4. If distorted, normalize: base operating income = base revenue × median margin. Disclose it.
5. If base operating income is negative **and** the median margin is also negative, a cash-flow
   valuation is not reliable. Report that and stop rather than producing a number.

### 5.5 Which accounting adjustments to apply

Reported accounting treats two large investments as expenses. Both are corrected by default.

| Adjustment | Effect on operating income | Effect on invested capital | Effect on debt |
|---|---|---|---|
| Capitalize R&D | `+ current R&D − amortization of research asset` | `+ unamortized research asset` | — |
| Capitalize leases | `+ implied lease interest` | `+ right-of-use asset` | `+ lease liability` |

**All-or-nothing rule.** Each adjustment propagates to every column in its row, or it is not applied
at all. Adjusting operating income without adjusting invested capital inflates return on capital,
which inflates fundamental growth, which inflates the valuation — a single omission compounding
three times. The audit enforces this rather than trusting it.

Goodwill is included in invested capital. Return on capital is reported both with and without it;
the with-goodwill figure drives the valuation.

### 5.6 Which currency to forecast in

| Policy | Forecast currency | What is translated | FX observations needed |
|---|---|---|---|
| `TranslateAtEnd` (default) | reporting currency | final per-share value only, at spot | one |
| `TranslateFlows` | output currency | each projected flow, at inflation-parity forwards | a forward curve |

The risk-free rate, cost of debt, terminal growth and discount rate all match the **forecast**
currency, not the output currency. The most common currency error in practice is adopting the
reader's preferred currency for the discount rate while leaving cash flows in the reporting
currency; the two policies above are each internally consistent and must never be combined.

### 5.7 Which beta to use

| Condition | Method |
|---|---|
| Sector unlevered beta available (default) | relever it at this company's own market debt-to-equity and effective tax rate |
| Unavailable, or policy forces it | regression beta, reported with R², observation count and window |

The chosen method, and why, is recorded. Policy decides; the engine does not pick opportunistically
based on which answer it prefers.

### 5.8 How country risk is computed

```
country_premium = max(0, spread(rating(country)) − spread(rating(base_market)))
                  × relative_equity_volatility
block_premium   = median of member-country premia
weighted        = Σ (weight × premium)
```

Resolution order for each exposure entry: `Country` directly; `Block` as the median over its
members; `Composite` as the median over the union of its blocks' members.

Three rules that are easy to get wrong:

- **Net against the base market.** Country risk is risk *above* a mature market, and the
  mature-market premium already embeds the base market's own risk. Never assume the base market is
  the top rating — read its rating from the data like any other country's. Hardcoding a zero base
  inflates every country's premium the moment the base market is downgraded.
- **Blocks are medians, not weighted averages.** No weighting data exists in the reference tables.
  Introducing population or output weights from elsewhere would put numbers into the engine that do
  not come from the data.
- **Report dispersion.** Blocks coarse enough to match real disclosure are not credit-homogeneous.
  Each block's internal spread is reported alongside its premium rather than hidden inside a median.

### 5.9 Which cost of debt to use

First available tier wins; the tier used is reported.

1. Yield to maturity on the company's traded straight bonds, where liquid quotes exist
2. Risk-free rate + default spread for the company's issuer rating
3. Risk-free rate + default spread from a synthetic rating derived from interest coverage
4. Interest expense ÷ average total debt — last resort, as it reflects historical coupons rather
   than current marginal borrowing cost

Tiers are never blended. If total debt is below 1% of total capital, the company is treated as
all-equity financed: debt weight zero, cost of capital equals cost of equity.

### 5.10 How capital is weighted

Equity at **market** value; debt at book value unless traded quotes exist. Weights must sum to one.
Capitalized lease liabilities are included in debt whenever leases are capitalized, consistent with
§5.5.

### 5.11 How growth is set

**Stage 1 — sustainable, from history.**

1. Take the trailing `roic_window` years of return on invested capital.
2. Exclude any year that is negative, or more than three times the median of the remaining years, as
   an outlier. Record each exclusion.
3. Apply `roic_statistic` (median by default) to what remains.
4. Repeat for the reinvestment rate.
5. `growth = return on capital × reinvestment rate`, capped at `high_growth_cap`.

The reinvestment rate may exceed 100% — growth funded by external capital is legitimate and is not
clamped. Where it does, how the funding gap is financed is reported.

Consensus estimates and management guidance are **cross-checks**, not inputs. Where guidance
conflicts with the fundamental calculation, the calculation governs and the divergence is reported.

**Stage 2 — transition, by interpolation.** Growth, return on capital and tax rate each move
linearly from their stage-1 value to their terminal value in equal annual increments. The reinvestment
rate is then *derived* each year as `growth ÷ return on capital`, never assumed.

The resulting return-on-capital path must be **continuous**: the final transition year sits one
increment from the terminal value. A discontinuity at the terminal boundary is a methodology failure,
not a rounding artifact, and the audit treats it as an error.

**Stage 3 — stable.**

```
stable_growth  = min(risk-free rate of forecast currency,
                     long-run inflation + long-run real growth of exposure-weighted markets)
stable_return  = cost of capital + moat_spread          # moat_spread defaults to 0
stable_reinvest = stable_growth ÷ stable_return
```

Hard constraint: stable growth cannot exceed the risk-free rate. If the selection rule returns more,
the risk-free rate binds.

`moat_spread` is a **sourced input**, because whether a competitive advantage will persist is not
calculable. What *is* calculable, and therefore computed: the realized return-on-capital spread over
cost of capital for every historical year, its average, and how many recent years sustained it. An
asserted spread exceeding the realized average is flagged. The engine supplies the evidence; it does
not form the judgement.

### 5.12 How the tax rate evolves

| Years | Rate |
|---|---|
| Base, 1–5 | effective rate, from taxes paid ÷ pre-tax income |
| 6–10 | linear convergence to the marginal statutory rate of the domicile |
| Terminal | marginal statutory rate |

Effective rates reflect timing differences, loss carryforwards and credits that do not persist in
perpetuity. Holding one forever is a permanent free lunch. Where a global-minimum-tax adjusted rate
binds, it is used.

### 5.13 How cash flow is projected

```
after_tax_operating_income(t) = after_tax_operating_income(t−1) × (1 + growth(t))
reinvestment(t)               = after_tax_operating_income(t) × reinvestment_rate(t)
cash_flow(t)                  = after_tax_operating_income(t) − reinvestment(t)
discount_factor(t)            = 1 ÷ (1 + cost_of_capital)^t        # or ^(t−0.5) if mid-period
```

Stock-based compensation does **not** appear. It is an operating expense already deducted inside
operating income, and it stays there — see §5.15.

### 5.14 How terminal value is set

Primary, Gordon growth:

```
terminal_flow  = after_tax_operating_income(final) × (1 + stable_growth) × (1 − stable_reinvest)
terminal_value = terminal_flow ÷ (cost_of_capital − stable_growth)
```

Cross-check, exit multiple: final-year operating earnings × the sector multiple. **The multiple must
match the adjustment state of the metric** — an R&D-adjusted earnings figure requires the
R&D-adjusted multiple, or the comparison is meaningless.

Checks: the spread between cost of capital and stable growth must exceed one percentage point, or
terminal value is numerically unstable; terminal value should be under 75% of total operating value;
the two methods should agree within 20%.

When terminal return on capital equals cost of capital, terminal value reduces algebraically to
`after_tax_operating_income ÷ cost_of_capital`. That identity is a free correctness test of the
entire terminal block and should be asserted.

### 5.15 How equity compensation is handled

Equity compensation creates two distinct claims, each handled exactly once, in a different place.

| Claim | Treatment | Where |
|---|---|---|
| Ongoing cost of future grants | expensed; left inside operating income, never added back | projection |
| Accumulated claim from past grants | valued at fair value, deducted as a senior claim | equity bridge |

Per-share value then divides by **shares outstanding**, not treasury-method diluted shares, because
the option claim has already been valued in full.

Adding the expense back treats a recurring real cost as free, inflating every projected cash flow.
The treasury stock method compounds it, capturing only intrinsic value and ignoring time value —
which for at- or out-of-the-money options is most of what they are worth.

**Fallback** when option-level data is unavailable: expense the compensation as above, use
treasury-method diluted shares, and omit the separate deduction. Exactly one of the two routes
applies. Combining them double-counts; combining either with an add-back is the error this rule
exists to prevent.

### 5.16 How equity value is derived

```
operating_asset_value = Σ present value of projected flows + present value of terminal value

equity_value = operating_asset_value
             − total debt (gross, including capitalized leases)
             + cash and marketable securities (gross)
             + non-operating assets and cross-holdings, at fair value
             − minority interests, at fair value
             − fair value of outstanding options and unvested awards

per_share = equity_value ÷ shares outstanding
```

Expressed in gross debt and gross cash deliberately. Writing the bridge in terms of net debt *and*
adding cash back subtracts debt once but adds cash twice. The sum of present values is operating
asset value, not enterprise value; non-operating items enter in the bridge, and the terminal-value
percentage check uses operating asset value as its denominator.

### 5.17 How the market-implied growth rate is found

Exactly one unknown: stage-1 growth. Everything else — cost of capital, returns, terminal
assumptions, margins, share count, the full bridge — is held at base case. Solve

```
valuation(growth) − market price per share = 0
```

by bisection over a fixed bracket, using a **fixed iteration count** rather than a tolerance test.
Value is monotone in stage-1 growth, so bisection is safe, and a fixed count cannot vary across
platforms the way an early-exit tolerance can.

Fixing the free variable is not optional. Without it the question is underdetermined: infinitely
many combinations of growth, margin, return and discount rate reproduce the same price.

### 5.18 How uncertainty is explored

| Analysis | Construction |
|---|---|
| Sensitivity grid | re-run across cost-of-capital and stable-growth offsets |
| Scenarios | re-run with explicit override records, not hand-written results |
| Simulation | re-run with sampled inputs, fixed seed, reported percentiles |

Simulation requires a **counter-based** random number generator, where draw *i* for variable *j* is
a pure function of seed, *i* and *j*. With a sequential generator, parallelism and reproducibility
become mutually exclusive; with a counter-based one, thread count cannot change the answer.

---

## 6. Determinism contract

The engine's premise is that a valuation can be reproduced years later. That requires more than
pure functions.

**Identity.** Every result carries a hash over the canonicalized inputs, the policy record, the
engine version and the dataset snapshot manifest. Two runs agreeing on the hash must agree on every
output number. Golden tests assert on the hash rather than on individual figures.

**Arithmetic.** Binary floating point is deterministic for the four basic operations and square root
given a fixed operation order. It is *not* deterministic across platforms for transcendental
functions, and compilers may legally reassociate. Therefore:

1. **Never use a power function for discount factors.** Compute `(1 + r)^t` by iterated
   multiplication. Power functions are not correctly rounded and vary across math library versions
   and platforms; iterated multiplication is bit-identical everywhere. This single rule removes the
   most likely source of cross-machine divergence in the whole engine.
2. No fast-math or fused-multiply-add contraction where the unfused form is the specified arithmetic.
3. Fixed summation order. Present values accumulate from the first year forward. No parallel
   reduction in any path reaching a reported number.
4. Fixed iteration counts in solvers, not tolerance-based early exits.
5. No unordered-container iteration in numeric paths.

**Representation.** Model in binary floating point; a discounted cash flow is not a ledger, and
exact decimal buys no accuracy where the inputs carry estimation error of several percent. Use exact
decimal only at the two boundaries: parsing reported statement values, which are exact decimal
quantities and must round-trip, and rendering. Round half-even at render time, to the currency's
minor unit for per-share figures and to four decimal places for rates.

**Currency.** Make currency part of a monetary value's type, so that adding two different currencies
is rejected at construction rather than discovered in a result. Conversion happens only through an
explicit rate carrying its own date and source. Where currency must be dynamic — reading a dataset
— keep a separate dynamic representation with one checked conversion into the static form, so there
is exactly one place a currency error can occur.

---

## 7. Audit

The audit is not a report section; it is the mechanism that makes the division of labour
enforceable. Each check yields a stable identifier, a severity, the actual value, the limit and a
message.

| Severity | Meaning |
|---|---|
| `Error` | the methodology is violated; the result may not be rendered as a conclusion |
| `Warn` | the result is usable but a stated threshold is breached |
| `Info` | a convention or selection worth recording |

Errors cover the rules that make a valuation internally coherent: stable growth within the risk-free
rate, an adequate spread between discount rate and stable growth, one currency throughout, the
growth-equals-return-times-reinvestment identity holding every year, a continuous return path,
accounting adjustments propagated completely, country risk netted against the base market, equity
compensation handled by exactly one route, and stage-1 assumptions grounded in history rather than
asserted.

Warnings cover thresholds that indicate strain rather than incoherence: terminal value share, method
divergence, base-year distortion, block dispersion, undisclosed exposure, computed cost of capital
against its sector benchmark, and an asserted moat spread exceeding realized history.

Because an `Error` blocks rendering, a valuation that violates the methodology fails loudly instead
of reading plausibly. That is the point: narrative layers can describe a result but cannot rescue
one.

---

## 8. Boundaries

### What is not the engine's job

| Task | Owner |
|---|---|
| Locating filings, transcripts, presentations | retrieval layer |
| Extracting values from documents | extraction layer, validated on ingest |
| Classifying a statement as fact, guidance or opinion | extraction layer |
| Assigning a company to a sector | curated input, persisted |
| Supplying geographic exposure weights | input, from the segment note |
| Selecting comparable companies | curated input, persisted |
| Asserting a durable competitive advantage | input, defaulting to none |
| Explaining a discrepancy the engine surfaced | narrative layer |
| Writing prose | narrative layer |

Everything else is arithmetic, and arithmetic belongs to the engine.

### The contract with a narrative layer

A narrative layer receives the result, the audit and the qualitative claims, and may describe,
compare, caveat and recommend. It may not alter a number, recompute a figure, or supply a value the
engine reported as missing. Where the engine reports a gap, the correct narrative response is to
state the gap and what it costs — not to fill it.

This is why intermediate columns are in the output. A layer that must recompute a discount factor to
render a table is a layer that can get it wrong.

### Extension points

- **Reference data refresh** — tables are versioned snapshots. A valuation names the snapshot it
  used, so a refresh re-dates rather than invalidates prior work.
- **New cross-checks** — additive to the cross-check list; no change to the core.
- **Alternative exposure bases** — the country-risk resolver takes exposure weights and a derivation
  rule; a different rule is a new policy value, not a rewrite.
- **Multi-segment valuation** — sum-of-the-parts is the core invoked per segment with segment-level
  inputs, then aggregated. The core needs no knowledge of segments.
