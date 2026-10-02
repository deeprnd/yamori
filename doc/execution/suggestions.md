Yes. Most of this prompt should be turned into a **deterministic valuation library**, leaving the model responsible mainly for source discovery, transcript extraction, ambiguous classifications, and explanation.

The prompt already defines formulas for FCFF, ROIC, reinvestment, WACC, terminal value, sensitivities, etc., so having an LLM calculate those repeatedly is unnecessary and introduces reproducibility risk. Pasted markdown The target should be: **same normalized inputs → byte-for-byte same valuation outputs**.

## 1. First define one canonical input type

Every number entering the engine should carry provenance:

```rust
struct DataPoint<T> {
    value: T,
    source: SourceId,
    source_type: SourceType,
    as_of: Date,
    period: Option<Period>,
    currency: Option<Currency>,
    confidence: Confidence,
}
```

Then something like:

```rust
struct ValuationInputs {
    company: CompanyInfo,
    market: MarketData,
    financials: Vec<FinancialPeriod>,
    geographic_revenue: Vec<GeographicRevenue>,
    consensus: Vec<ConsensusPeriod>,
    securities: DilutionInputs,

    risk_free_rate: DataPoint<Rate>,
    mature_market_erp: DataPoint<Rate>,
    country_risk_premiums: Vec<CountryRiskPremium>,
    sector_unlevered_beta: Option<DataPoint<f64>>,
    industry_multiples: IndustryMultiples,

    fx: FxSnapshot,

    assumptions: ValuationPolicy,
}
```

`source`, `date`, `period`, and currency should **never** live only in prose. The final source table required by the prompt can then be generated automatically. The prompt explicitly requires source/date transparency and reproducibility. Pasted markdown

---

# 2. Data resolution functions

Before valuation mathematics, implement deterministic selection/normalization.

The prompt gives an explicit source priority — filings first, calculated ratios second, transcripts third, etc. Pasted markdown

```text
resolve_input(field, candidates, source_policy)
select_latest_fiscal_period(periods)
select_ttm(periods)
build_ttm(quarters)
validate_period_completeness(period)
detect_stale_input(datapoint, reference_date)
detect_conflicting_values(candidates, tolerance)
convert_money(amount, fx_rate)
normalize_units(value)
```

Most importantly:

```text
resolve_input(...)
```

should encode rules such as:

```text
company filing
    > supplied financial statement
    > supplied calculated metric
    > earnings report
    > analyst consensus
    > external database
```

It should return both:

```text
selected_value
rejected_alternatives[]
resolution_reason
```

Then the LLM doesn't decide which revenue number to use.

---

# 3. Financial statement calculation functions

These should all be pure functions.

### Income statement

```text
ebit_margin(revenue, ebit)
effective_tax_rate(tax_expense, pretax_income)
nopat(ebit, tax_rate)
```

### Balance sheet

```text
total_debt(short_term_debt, long_term_debt)
net_debt(total_debt, cash_and_marketable_securities)
invested_capital(debt, equity, cash)
average_invested_capital(beginning, ending)
average_debt(beginning, ending)
```

### Cash flow

```text
net_capex(capex, depreciation_amortization)
reinvestment(net_capex, change_working_capital)
reinvestment_rate(reinvestment, nopat)

fcff(
    nopat,
    depreciation_amortization,
    capex,
    change_working_capital
)

fcff_from_reinvestment_rate(
    nopat,
    reinvestment_rate
)
```

Those correspond directly to the formulas specified in the prompt. Pasted markdown

I would calculate FCFF both ways and add:

```text
validate_fcff_reconciliation(...)
```

to flag material discrepancies.

---

# 4. Historical metric engine

For every historical year:

```text
revenue_growth(current_revenue, previous_revenue)
ebit_growth(current_ebit, previous_ebit)
ebit_margin(revenue, ebit)

roic(nopat, invested_capital)
reinvestment_rate(reinvestment, nopat)
fundamental_growth(roic, reinvestment_rate)
```

Then:

```text
calculate_historical_metrics(financial_periods)
```

returns:

```text
year
revenue
revenue_growth
ebit
ebit_margin
nopat
invested_capital
roic
net_capex
change_wc
reinvestment
reinvestment_rate
implied_growth
```

The five-year analysis requested by the prompt becomes just rendering this result rather than asking the model to calculate it. Pasted markdown

---

# 5. Fully diluted share calculation

This should definitely not be done by the LLM.

```text
treasury_stock_method(
    options,
    strike_price,
    current_share_price
)

incremental_option_shares(...)
rsu_dilution(...)
convertible_dilution(...)
fully_diluted_shares(...)
```

Something like:

```text
FD shares =
    basic shares
  + incremental option shares
  + unvested RSUs
  + dilutive convertibles
  + other dilutive securities
```

Store the breakdown because the prompt requires fully diluted shares and explicitly ties this to SBC treatment. Pasted markdown

Also:

```text
validate_sbc_treatment(...)
```

to ensure the engine never simultaneously uses a cash SBC deduction and diluted shares when the selected methodology says not to. The prompt explicitly requires this consistency. Pasted markdown

---

# 6. Country-risk engine

Once geographical revenues and the Damodaran table are normalized:

```text
map_region_to_countries(...)
normalize_geographic_revenue_weights(...)
lookup_country_crp(country, crp_dataset)
weighted_country_risk_premium(exposures)
```

Core operation:

```text
weighted_crp =
    Σ revenue_weight[country] * crp[country]
```

Have the function return the entire contribution table automatically.

This calculation is explicitly prescribed in the methodology. Pasted markdown

The only nondeterministic part should be cases like:

> "Europe = 27% revenue"

but no country split exists.

Even there I would avoid asking the LLM for a number directly. Instead let it produce structured input:

```json
{
  "region": "Europe",
  "method": "gdp_weighted",
  "countries": [...]
}
```

and have deterministic code calculate the regional CRP.

---

# 7. Beta functions

Both permitted methods can be deterministic.

### Bottom-up beta

```text
relever_beta(
    unlevered_beta,
    tax_rate,
    debt_to_equity
)

bottom_up_beta(...)
```

Formula:

```text
βL = βU × [1 + (1 - tax) × D/E]
```

### Regression beta

Given price history:

```text
calculate_periodic_returns(...)
align_return_series(...)
ols_beta(company_returns, benchmark_returns)
r_squared(...)
```

Return:

```text
beta
alpha
r_squared
observations
start_date
end_date
frequency
```

Then a deterministic policy can say:

```text
if valid_sector_beta exists:
    use bottom_up_beta
else:
    use regression_beta
```

rather than having the model choose opportunistically. The two alternatives are specified by the prompt. Pasted markdown

---

# 8. WACC engine

This entire section should be code.

```text
cost_of_equity(
    risk_free_rate,
    beta,
    mature_market_erp,
    weighted_crp
)

cost_of_debt_from_interest(
    interest_expense,
    average_debt
)

after_tax_cost_of_debt(
    pretax_cost_of_debt,
    tax_rate
)

equity_weight(market_cap, debt)
debt_weight(market_cap, debt)

wacc(
    equity_weight,
    cost_of_equity,
    debt_weight,
    after_tax_cost_of_debt
)
```

Then:

```text
validate_wacc_currency(...)
validate_capital_weights(...)
```

For example:

```text
assert(E_weight + D_weight ~= 1.0)
assert(risk_free.currency == valuation_currency)
assert(fcff.currency == valuation_currency)
```

This directly covers the formulas and currency rules in the prompt. Pasted markdown Pasted markdown

---

# 9. Growth assumption engine

This is where the current prompt still leaves too much discretion to the model.

I'd convert the discretion into a configurable **policy**.

For example:

```rust
struct GrowthPolicy {
    historical_roic_method: RoicMethod,
    historical_years: usize,
    high_growth_cap: Rate,            // 25%
    transition_years: usize,          // 5
    stable_growth: StableGrowthPolicy,
    stable_roic_spread: Rate,         // normally 0
}
```

Functions:

```text
historical_sustainable_roic(history, policy)
historical_reinvestment_rate(history, policy)

fundamental_growth(
    roic,
    reinvestment_rate
)

cap_high_growth(
    growth,
    25%
)

consensus_growth(consensus)
management_guidance_range(extracted_guidance)
```

And:

```text
build_stage1_assumptions(...)
build_transition_path(...)
build_terminal_assumptions(...)
```

### Transition

Make decay mathematical:

```text
linear_interpolate(start, end, periods)
```

Thus years 6–10 can deterministically produce:

```text
growth_y6 ... growth_y10
roic_y6 ... roic_y10
```

and:

```text
reinvestment_rate_y =
    growth_y / roic_y
```

This implements the prompt's three-stage framework. Pasted markdown

---

# 10. Stable-growth functions

```text
validate_terminal_growth(
    stable_growth,
    risk_free_rate
)

stable_roic(
    wacc,
    moat_spread
)

stable_reinvestment_rate(
    stable_growth,
    stable_roic
)
```

Important design choice:

```text
moat_spread = 0
```

should be the deterministic default.

If somebody wants `WACC + 2%`, that should be an **explicit sourced assumption**, not something the model silently decides.

---

# 11. Ten-year FCFF projection

One central function:

```text
project_fcff(
    base_nopat,
    growth_path[10],
    roic_path[10],
    reinvestment_rate_path[10],
    sbc_path[10],
    wacc
)
```

For each year:

```text
NOPAT_t = NOPAT_(t-1) × (1 + g_t)

Reinvestment_t =
    NOPAT_t × reinvestment_rate_t

FCFF_t =
    NOPAT_t - Reinvestment_t + SBC_adjustment_t

PVFactor_t =
    1 / (1 + WACC)^t

PV_FCFF_t =
    FCFF_t × PVFactor_t
```

The projection structure follows the requested DCF table. Pasted markdown

Return the complete rows. Don't make the rendering layer recompute anything.

---

# 12. Terminal-value engine

```text
terminal_fcff(
    year10_nopat,
    stable_growth,
    stable_reinvestment_rate
)

gordon_terminal_value(
    terminal_fcff,
    wacc,
    stable_growth
)

discount_terminal_value(
    terminal_value,
    wacc,
    years
)
```

Cross-check:

```text
exit_multiple_terminal_value(
    year10_ebitda,
    exit_ev_ebitda
)

terminal_value_share_of_ev(...)
implied_terminal_ev_ebitda(...)
implied_terminal_pe(...)
terminal_method_difference(...)
```

And validations:

```text
assert(wacc > stable_growth)

warn_if(
    terminal_value_share > 75%
)

warn_if(
    abs(gordon_tv - multiple_tv) / gordon_tv > 20%
)
```

These thresholds are already specified in the prompt. Pasted markdown

---

# 13. Enterprise → equity value bridge

Functions:

```text
enterprise_value(
    pv_forecast_fcff,
    pv_terminal_value
)

equity_value(
    enterprise_value,
    debt,
    cash,
    minority_interest,
    non_operating_assets,
    cross_holdings,
    lease_adjustments
)

intrinsic_value_per_share(
    equity_value,
    fully_diluted_shares
)
```

There is an important issue in the current prompt here.

It defines:

```text
Net debt = total debt - cash
```

but later says:

```text
Equity Value = EV - Net Debt + Cash
```

That double-counts cash. Pasted markdown Pasted markdown

The engine should use **one** of:

```text
Equity = EV - Debt + Cash
```

or:

```text
Equity = EV - NetDebt
```

but never:

```text
EV - NetDebt + Cash
```

I would fix this in the methodology before implementing it.

---

# 14. FX engine

```text
fx_convert(value, from_currency, to_currency, rate)
translate_financial_period(...)
translate_market_price(...)
translate_equity_value(...)
validate_fx_dates(...)
validate_single_valuation_currency(...)
```

I'd make it impossible for downstream functions to mix currencies:

```rust
Money<EUR>
Money<USD>
```

or runtime equivalent.

Then:

```text
add(Money<EUR>, Money<USD>)
```

should fail.

That eliminates an entire class of valuation errors that the prompt explicitly warns about. Pasted markdown

---

# 15. Relative-value functions

Once comparables are supplied:

```text
enterprise_value_from_market_data(...)
pe_ratio(...)
ev_ebitda(...)
price_sales(...)

median_multiple(peers, metric)
percentile_multiple(peers, metric)

implied_equity_value_from_pe(...)
implied_ev_from_ev_ebitda(...)
```

The **math** is deterministic.

Peer selection is not entirely deterministic, so separate:

```text
select_comparable_candidates(...)
```

from:

```text
calculate_comparable_metrics(...)
```

Ideally peer membership is persisted as an explicit input rather than recreated by an LLM on every valuation.

---

# 16. Reverse DCF

This should absolutely be code.

Define exactly one unknown, for example Stage-1 growth:

```text
valuation_for_growth(g)
```

Then root solve:

```text
solve_implied_growth(
    target_market_price,
    lower_bound,
    upper_bound
)
```

with bisection or Brent's method:

```text
DCF(g_implied) - market_price = 0
```

Everything except `g_high` remains at base-case assumptions.

Otherwise "market-implied growth" is underdetermined because infinitely many combinations of growth, margins, ROIC and WACC produce the same price.

The prompt asks explicitly for this reverse DCF. Pasted markdown

---

# 17. Sensitivity engine

Pure function:

```text
sensitivity_matrix(
    base_model,
    wacc_offsets = [-1%, -0.5%, 0, +0.5%, +1%],
    growth_offsets = [-0.5%, 0, +0.5%]
)
```

Returns a matrix of IV/share.

No LLM arithmetic at all.

Similarly:

```text
run_scenario(base_inputs, scenario_overrides)
```

with explicit:

```rust
struct ScenarioOverrides {
    growth: Option<...>,
    margin: Option<...>,
    roic: Option<...>,
    wacc: Option<...>,
    stable_growth: Option<...>,
}
```

The prompt requires both. Pasted markdown

---

# 18. Monte Carlo engine

If you want to make the "conceptual" Monte Carlo real:

```text
run_monte_carlo(
    model,
    distributions,
    iterations,
    seed
)
```

Always accept a fixed:

```text
seed
```

for reproducibility.

Return:

```text
p5
p10
p25
median
p75
p90
p95
mean
std_dev
```

The LLM should summarize those outputs, not simulate uncertainty itself.

---

# 19. Deterministic audit engine

This should be one of the most important modules.

```text
audit_valuation(model) -> Vec<AuditCheck>
```

Checks:

```text
check_fully_diluted_shares()
check_sbc_not_double_counted()
check_current_market_wacc()
check_terminal_growth_le_risk_free()
check_terminal_roic()
check_growth_reinvestment_identity()
check_effective_tax_rate()
check_country_risk_weighting()
check_terminal_value_percentage()
check_cross_check_count()
check_currency_consistency()
check_fx_date_consistency()
check_source_coverage()
```

Each returns something structured:

```json
{
  "id": "TERMINAL_G_LT_RF",
  "status": "PASS",
  "actual": 0.021,
  "limit": 0.026,
  "message": "Stable growth <= risk-free rate"
}
```

That maps almost one-to-one to Step 10. Pasted markdown

---

# 20. What should remain with the LLM?

Very little calculation.

I would restrict it to:

| Task | LLM? | Deterministic code? |
|---|---:|---:|
| Find latest filing | ✓ | source validation |
| Extract values from filing | ✓/parser | validation |
| Pick latest TTM | | ✓ |
| Calculate EBIT margin | | ✓ |
| Calculate ROIC | | ✓ |
| Calculate FCFF | | ✓ |
| Calculate beta | | ✓ |
| Calculate CRP | | ✓ |
| Calculate WACC | | ✓ |
| Growth × reinvestment | | ✓ |
| 10-year DCF | | ✓ |
| Terminal value | | ✓ |
| FX translation | | ✓ |
| Diluted shares | | ✓ |
| Reverse DCF | | ✓ |
| Sensitivity | | ✓ |
| Monte Carlo | | ✓ |
| Audit | | ✓ |
| Extract management claims | ✓ | |
| Classify statement as fact/guidance/opinion | ✓ | |
| Explain discrepancy | ✓ | |
| Identify qualitative moat evidence | ✓ | |
| Write final narrative | ✓ | |

The prompt already says transcripts should be used qualitatively to adjust/validate assumptions rather than as financial-history substitutes. Pasted markdown

So ideally the transcript component produces structured facts like:

```json
{
  "type": "guidance",
  "metric": "revenue_growth",
  "period": "FY2027",
  "low": 0.12,
  "high": 0.15,
  "quote_ref": "...",
  "source": "...",
  "date": "..."
}
```

The valuation engine then compares those against its deterministic fundamental-growth calculation.

---

## Architecture I'd use

```text
                  ┌───────────────────────┐
                  │ Retrieval / filings   │
                  │ APIs / web / uploads │
                  └──────────┬────────────┘
                             │
                             ▼
                  ┌───────────────────────┐
                  │ Extraction layer      │
                  │ LLM + parsers         │
                  └──────────┬────────────┘
                             │
                         typed inputs
                             │
                             ▼
              ┌──────────────────────────────┐
              │ Input Resolver / Validator   │
              │ source priority, periods, FX │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │ Deterministic Valuation Core │
              │                              │
              │ financial metrics            │
              │ dilution                     │
              │ beta / CRP / WACC            │
              │ growth                       │
              │ projections                  │
              │ terminal value               │
              │ equity bridge                │
              │ reverse DCF                  │
              │ sensitivity / scenarios      │
              │ cross-checks                 │
              └──────────────┬───────────────┘
                             │
                             ▼
                    ValuationResult
                             │
                ┌────────────┴────────────┐
                ▼                         ▼
        deterministic audit         LLM renderer
                                   narrative only
```

### The important API boundary

The LLM should effectively receive:

```text
ValuationResult
AuditResult
QualitativeEvidence
```

and be told:

> Do not calculate or change any numeric valuation result. Explain and render the supplied results.

That is much safer than giving it raw statements and asking it to execute the entire prompt.

---

## I would also change four underspecified parts before implementation

Besides the **net-debt/cash double-counting bug**, there are several places where the current prompt still permits different answers from identical data:

1. **"Average recent ROIC adjusted for trend"** needs an exact algorithm. Specify e.g. trailing-3-year median, weighted mean, or regression.
2. **Cost of debt** currently allows either interest/average debt or bond yield. Define deterministic priority and fallback.
3. **Stable growth** gives a ceiling but not an actual selection algorithm. Make it an explicit policy/input.
4. **Reverse DCF** needs to specify exactly which variable is solved for while all others remain fixed.

Those are precisely the places where two otherwise correct implementations can produce different valuations.

The ideal end state is therefore not a "valuation prompt" doing calculations. It is a **valuation program with a prompt-based research/explanation layer around it**. The numerical core can be almost entirely deterministic; the genuinely subjective inputs become explicit, sourced parameters rather than hidden model judgments.