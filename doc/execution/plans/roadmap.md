
# Backend policy

Yamori implements the Damodaran methodology by composing third-party primitives; it does not implement CSV parsers, arithmetic kernels, statistics algorithms, interpolation, solvers, RNGs, or probability distributions itself.

# Milestone 1 — CSV Ratio Engine

Read a financial CSV, calculate ratios element-wise across all periods, and write the enriched dataset back to CSV; the demo recomputes metrics such as P/E and Book Value per Share from the supplied STLA file.

## Epic 1.1 — CSV Financial Frame

Load the supplied `Metric × Period` CSV, expose each metric as a period series, modify it, and write the same financial-table shape back to CSV.

### Story — Integrate Apache Arrow CSV

**Library: Apache Arrow C++ CSV** — Add Arrow CSV reader/writer and prove an unchanged STLA file can be loaded and emitted successfully.

### Story — Read Financial CSV

**Library: Apache Arrow C++ CSV** — Parse metric names, period columns, numeric values, and nulls into an Arrow-backed financial frame.

### Story — Metric Series View

**Library: Apache Arrow Arrays** — Expose a metric such as `Stock Price` as one numeric series spanning all available periods.

### Story — Preserve Missing Values

**Library: Apache Arrow Arrays** — Represent unavailable historical/forecast observations with Arrow validity semantics rather than sentinel numbers.

### Story — Write Financial CSV

**Library: Apache Arrow C++ CSV** — Convert the modified financial frame back into `Metric × Period` CSV output.

## Epic 1.2 — Element-wise Financial Math

Calculate a ratio across every period with one operation; the demo computes `P/E = Stock Price / EPS` and `Book Value per Share = Equity / Shares`.

### Story — Integrate Arrow Compute

**Library: Apache Arrow Compute** — Enable the compute registry and wrap scalar/array invocation behind Yamori operations.

### Story — Series Arithmetic

**Library: Apache Arrow Compute** — Support element-wise `add`, `subtract`, `multiply`, and `divide` between aligned metric series.

### Story — Scalar Broadcasting

**Library: Apache Arrow Compute** — Apply scalar values to entire series using Arrow's scalar/array broadcasting.

### Story — Power and Basic Math

**Library: Apache Arrow Compute** — Expose the backend `power`, `abs`, `sqrt`, `ln`, `exp`, and related kernels required by valuation formulas.

### Story — Comparisons

**Library: Apache Arrow Compute** — Produce boolean series from `<`, `<=`, `>`, `>=`, `==`, and `!=`.

### Story — Conditional Values

**Library: Apache Arrow Compute** — Use `if_else`/mask operations for conditional financial calculations without application loops.

### Story — Null Propagation

**Library: Apache Arrow Compute** — Preserve Arrow null semantics through every element-wise calculation.

## Epic 1.3 — Financial Series Operations

Calculate growth, historical changes, and summary statistics over complete financial series; the demo derives revenue growth and historical medians from CSV data.

### Story — Integrate Arrow Series Kernels

**Library: Apache Arrow Compute** — Bind cumulative, pairwise, aggregate, slicing, and concatenation operations required by financial series.

### Story — Period Shift

**Library: Apache Arrow Arrays/Compute** — Produce lagged metric series through Arrow slicing and concatenation.

### Story — Period Difference

**Library: Apache Arrow Compute** — Use `pairwise_diff` for absolute period-over-period changes.

### Story — Percentage Change

**Library: Apache Arrow Compute** — Compose shift, subtraction, and division kernels into period-over-period percentage change.

### Story — Cumulative Operations

**Library: Apache Arrow Compute** — Expose cumulative sum, product, minimum, maximum, and mean.

### Story — Reductions

**Library: Apache Arrow Compute** — Expose sum, mean, min, max, variance, standard deviation, and quantile operations.

### Story — CAGR

**Library: Apache Arrow Compute** — Compose backend divide and power operations into CAGR without implementing a numerical kernel.

## Epic 1.4 — Ratio Formula Engine

Define financial metrics as named dependency graphs over source metrics; the demo rebuilds selected existing STLA ratio rows and persists them back to CSV.

### Story — Integrate Formula-to-Arrow Adapter

**Library: Apache Arrow Compute** — Map Yamori formula nodes directly to Arrow compute functions rather than implementing operators.

### Story — Named Formula

**Library: Yamori orchestration + Arrow Compute** — Describe a derived metric by name, required source metrics, and backend operations.

### Story — Formula Dependencies

**Library: Yamori orchestration** — Resolve derived-metric dependencies in deterministic order without performing numerical work itself.

### Story — Per-share Ratios

**Library: Apache Arrow Compute** — Compose division kernels for Book Value/Share, Revenue/Share, FCF/Share, Cash/Share, and equivalent ratios.

### Story — Valuation Multiples

**Library: Apache Arrow Compute** — Compose series arithmetic for P/E, P/B, P/S, EV/EBIT, EV/EBITDA, and associated yields.

### Story — Margin Ratios

**Library: Apache Arrow Compute** — Compose division kernels for gross, EBIT, EBITDA, net-income, and FCF margins.

### Story — Return Ratios

**Library: Apache Arrow Compute** — Compose arithmetic kernels for ROIC, ROE, ROA, and related return metrics.

### Story — Leverage Ratios

**Library: Apache Arrow Compute** — Compose arithmetic kernels for Debt/Equity, Debt/Capital, Net Debt/EBITDA, and related metrics.

### Story — Replace Existing Ratio

**Library: Apache Arrow Arrays** — Replace imported ratio values with independently recomputed values while retaining the metric identity.

### Story — Append Calculated Ratio

**Library: Apache Arrow Arrays** — Add a newly calculated metric series to the financial frame.

## Epic 1.5 — Ratio Pipeline Demo

Run the complete CSV → calculate → CSV workflow against a real financial dataset.

### Story — Integrate Ratio Pipeline

**Library: Arrow CSV + Arrow Compute** — Connect ingestion, formula evaluation, metric replacement/appending, and output into one executable workflow.

### Story — STLA P/E Demo

**Library: Arrow Compute** — Recompute P/E across every period with sufficient inputs and compare against the supplied row.

### Story — STLA Book Value per Share Demo

**Library: Arrow Compute** — Compute book value per share across periods from book equity and shares outstanding.

### Story — STLA Multi-ratio Demo

**Library: Arrow Compute** — Recompute a representative set of valuation, return, margin, and leverage ratios in one pass.

### Story — Persist Calculated CSV

**Library: Apache Arrow CSV** — Produce an enriched CSV containing the calculated ratio series.

---

# Milestone 2 — Damodaran Valuation Math

Add only the additional deterministic capabilities required by the valuation prompt, excluding the option-pricing branch explicitly left out of this scope; the milestone ends with one complete deterministic DCF.

## Epic 2.1 — Historical Valuation Metrics

Turn historical statement data into the five-year ROIC, reinvestment, fundamental-growth, and normalized-base-year evidence required by the methodology.

### Story — Integrate GSL Statistics

**Library: GNU GSL Statistics** — Add GSL median/order-statistic support for the historical selection rules.

### Story — NOPAT

**Library: Apache Arrow Compute** — Compose multiply and subtract kernels for `EBIT × (1 − tax rate)`.

### Story — Invested Capital

**Library: Apache Arrow Compute** — Compose source balance-sheet series into the methodology's invested-capital definition.

### Story — ROIC

**Library: Apache Arrow Compute** — Divide NOPAT by invested capital across historical periods.

### Story — Net Reinvestment

**Library: Apache Arrow Compute** — Compose CapEx, D&A, and working-capital changes into historical reinvestment.

### Story — Reinvestment Rate

**Library: Apache Arrow Compute** — Divide historical reinvestment by NOPAT.

### Story — Fundamental Growth

**Library: Apache Arrow Compute** — Multiply ROIC by reinvestment rate as required by the methodology.

### Story — Historical Median

**Library: GNU GSL Statistics** — Calculate the historical medians used for sustainable inputs and base-year normalization.

### Story — Outlier Rule

**Library: GSL Statistics + Arrow Compute** — Use GSL median plus Arrow comparisons to apply the methodology's negative and `3× median` exclusion rules.

### Story — Base-year Distortion

**Library: GSL Statistics + Arrow Compute** — Compare current margins against the five-year median and apply the 30% distortion test.

### Story — Base-year Normalization

**Library: Apache Arrow Compute** — Calculate normalized EBIT from revenue and historical median margin when required.

## Epic 2.2 — Accounting Adjustments

Apply the R&D and lease transformations required before ROIC and valuation; the demo shows adjusted EBIT and invested capital from raw financial inputs.

### Story — Integrate Adjustment Kernels

**Library: Apache Arrow Compute** — Bind the arithmetic, cumulative, slicing, and reduction kernels needed by adjustment schedules.

### Story — R&D Research Asset

**Library: Apache Arrow Compute** — Compose historical R&D series, amortization weights, multiplication, and summation into the unamortized research asset.

### Story — R&D-adjusted EBIT

**Library: Apache Arrow Compute** — Calculate reported EBIT plus current R&D less research-asset amortization.

### Story — R&D-adjusted Invested Capital

**Library: Apache Arrow Compute** — Add the unamortized research asset to invested capital.

### Story — Lease-adjusted Debt

**Library: Apache Arrow Compute** — Add supplied capitalized lease obligations consistently to debt.

### Story — Lease-adjusted EBIT

**Library: Apache Arrow Compute** — Apply the methodology's supplied lease adjustment consistently to operating income.

### Story — Adjustment Consistency

**Library: Yamori orchestration** — Ensure each enabled adjustment feeds every required financial quantity without implementing new mathematics.

## Epic 2.3 — Cost of Capital

Calculate bottom-up beta, country risk, cost of equity, cost of debt, capital weights, and WACC; the demo emits every Step 2 component.

### Story — Integrate Cost-of-Capital Kernels

**Library: Apache Arrow Compute** — Route all weighted arithmetic and scalar formulas through Arrow Compute.

### Story — Beta Relevering

**Library: Apache Arrow Compute** — Compose the sector beta, tax rate, and subject-company D/E into bottom-up beta.

### Story — Country Risk Contributions

**Library: Apache Arrow Compute** — Multiply geographic exposure weights by country/block CRPs element-wise.

### Story — Weighted CRP

**Library: Apache Arrow Compute** — Sum the country-risk contributions into one weighted premium.

### Story — Cost of Equity

**Library: Apache Arrow Compute** — Compose `Rf + beta × ERP + CRP`.

### Story — Interest Coverage

**Library: Apache Arrow Compute** — Calculate EBIT divided by interest expense for synthetic-rating lookup.

### Story — Cost of Debt

**Library: Apache Arrow Compute** — Compose risk-free rate, selected default spread, and tax effect into Kd.

### Story — Capital Weights

**Library: Apache Arrow Compute** — Calculate market-value equity and debt weights.

### Story — WACC

**Library: Apache Arrow Compute** — Compose weighted Ke and after-tax Kd into WACC.

## Epic 2.4 — Three-stage Growth Model

Produce the complete high-growth, transition, and stable-growth schedule required by the methodology.

### Story — Integrate GSL Interpolation

**Library: GNU GSL Interpolation** — Add linear interpolation for deterministic transition paths.

### Story — Sustainable ROIC

**Library: GNU GSL Statistics** — Derive Stage 1 ROIC from the methodology's filtered trailing historical values.

### Story — Sustainable Reinvestment

**Library: GNU GSL Statistics** — Derive Stage 1 reinvestment rate from the filtered trailing historical values.

### Story — High-growth Rate

**Library: Apache Arrow Compute** — Multiply sustainable ROIC by sustainable reinvestment and enforce the methodology's explicit cap.

### Story — Growth Transition

**Library: GNU GSL Interpolation** — Generate the linear Year 6–10 transition from Stage 1 growth to stable growth.

### Story — ROIC Transition

**Library: GNU GSL Interpolation** — Generate the continuous linear transition from Stage 1 ROIC to terminal ROIC.

### Story — Tax Transition

**Library: GNU GSL Interpolation** — Generate the effective-to-marginal tax-rate convergence path.

### Story — Derived Reinvestment Path

**Library: Apache Arrow Compute** — Divide each year's growth by its corresponding ROIC.

### Story — Stable Growth

**Library: Apache Arrow Compute** — Select and constrain terminal growth according to the supplied risk-free and macro assumptions.

## Epic 2.5 — Ten-year FCFF Projection

Project the complete ten-year operating model and FCFF schedule; the demo emits every numeric column in Step 4.

### Story — Integrate Projection Kernels

**Library: Apache Arrow Compute** — Bind the arithmetic and cumulative kernels needed to evolve forecast series.

### Story — EBIT Path

**Library: Apache Arrow Compute** — Apply the growth path to produce annual EBIT values.

### Story — NOPAT Path

**Library: Apache Arrow Compute** — Apply each year's tax rate to projected EBIT.

### Story — Reinvestment Path

**Library: Apache Arrow Compute** — Multiply projected NOPAT by the corresponding reinvestment rate.

### Story — FCFF Path

**Library: Apache Arrow Compute** — Subtract reinvestment from NOPAT for every forecast year.

## Epic 2.6 — Discounting and Terminal Value

Discount the explicit forecast and calculate Gordon-growth terminal value; the demo produces operating asset value and terminal-value share.

### Story — Integrate Discounting Kernels

**Library: Apache Arrow Compute** — Use backend multiplication/division for the deterministic discount-factor recurrence rather than implementing a math kernel.

### Story — Discount-factor Path

**Library: Apache Arrow Compute** — Generate the prompt's end-of-period discount factors through repeated backend multiplication.

### Story — Discounted FCFF

**Library: Apache Arrow Compute** — Multiply forecast FCFF by the corresponding discount-factor series.

### Story — Explicit-period PV

**Library: Apache Arrow Compute** — Reduce discounted FCFF to one present value.

### Story — Stable Reinvestment

**Library: Apache Arrow Compute** — Calculate `g_stable / ROIC_stable`.

### Story — Year-11 FCFF

**Library: Apache Arrow Compute** — Compose terminal growth, terminal tax, and stable reinvestment into FCFF₁₁.

### Story — Gordon Terminal Value

**Library: Apache Arrow Compute** — Calculate `FCFF₁₁ / (WACC − g_stable)`.

### Story — Terminal PV

**Library: Apache Arrow Compute** — Apply the matching Year-10 discount factor to terminal value.

### Story — Terminal-value Share

**Library: Apache Arrow Compute** — Calculate terminal PV as a percentage of total operating asset value.

## Epic 2.7 — Equity Value and Cross-checks

Convert operating value into per-share intrinsic value and calculate the prompt's multiple-based checks.

### Story — Integrate Equity-bridge Kernels

**Library: Apache Arrow Compute** — Route bridge arithmetic and implied-multiple calculations through Arrow Compute.

### Story — Operating Asset Value

**Library: Apache Arrow Compute** — Add explicit-period PV and terminal-value PV.

### Story — Equity Bridge

**Library: Apache Arrow Compute** — Apply debt, cash, non-operating assets, cross-holdings, and minority interests to operating asset value.

### Story — Per-share Intrinsic Value

**Library: Apache Arrow Compute** — Divide equity value by the supplied applicable share count.

### Story — Final FX Translation

**Library: Apache Arrow Compute** — Apply the single supplied spot FX conversion required by the default methodology.

### Story — Implied P/E

**Library: Apache Arrow Compute** — Calculate the earnings multiple implied by intrinsic equity value.

### Story — Implied P/S

**Library: Apache Arrow Compute** — Calculate the sales multiple implied by intrinsic equity value.

### Story — Implied EV/EBITDA

**Library: Apache Arrow Compute** — Calculate the operating multiple implied by the DCF.

### Story — Exit-multiple Cross-check

**Library: Apache Arrow Compute** — Calculate secondary terminal value from supplied EBITDA and industry exit multiple.

## Epic 2.8 — Reverse DCF

Solve for the Stage 1 growth rate implied by the current market price using the exact fixed-iteration methodology in the prompt.

### Story — Integrate GSL Root Solver

**Library: GNU GSL Roots** — Add `gsl_root_fsolver_bisection` behind the Yamori reverse-DCF adapter.

### Story — DCF Objective Callback

**Library: GSL Roots + existing valuation pipeline** — Expose `DCF(g_high) − market_price` as the solver callback while holding all other assumptions fixed.

### Story — Fixed 100 Iterations

**Library: GNU GSL Roots** — Advance the GSL bisection solver exactly 100 times rather than using its tolerance-based stopping criterion.

### Story — Implied Growth Result

**Library: GNU GSL Roots** — Return the solved Stage 1 growth rate and corresponding intrinsic value.

## Epic 2.9 — Sensitivity and Scenarios

Run the existing valuation function repeatedly over the prompt's WACC/growth grid and named assumption sets.

### Story — Integrate Batch Valuation Runner

**Library: Yamori orchestration + existing Arrow/GSL backends** — Execute repeated valuation calls without introducing a second mathematical implementation.

### Story — WACC/Growth Grid

**Library: Existing Yamori valuation pipeline** — Evaluate every cell in the required two-dimensional sensitivity matrix.

### Story — Scenario Inputs

**Library: Yamori orchestration** — Represent bull, base, bear, and stress cases as complete input sets.

### Story — Scenario Execution

**Library: Existing Yamori valuation pipeline** — Re-run the identical deterministic model for every scenario.

## Epic 2.10 — Deterministic Valuation Demo

Run one company's CSV-derived financials through the entire deterministic methodology to intrinsic value, reverse DCF, cross-checks, sensitivity, and scenarios.

### Story — Integrate End-to-End Pipeline

**Library: Arrow CSV + Arrow Compute + GSL Statistics + GSL Interpolation + GSL Roots** — Connect all Milestone 1–2 backends behind one executable valuation workflow.

### Story — Golden Company Valuation

**Library: Existing Yamori pipeline** — Freeze one complete valuation with expected intermediate values as the regression baseline.

---

# Milestone 3 — Monte Carlo Valuation

Add uncertainty distributions around the completed deterministic valuation using third-party RNG and distribution algorithms; the valuation itself remains the Milestone 2 implementation.

## Epic 3.1 — Random Sampling

Generate reproducible samples for uncertain valuation assumptions; the demo produces the same sampled inputs for the same seed.

### Story — Integrate GSL RNG

**Library: GNU GSL RNG** — Add explicit seeded generator lifecycle and backend selection.

### Story — Integrate GSL Random Distributions

**Library: GNU GSL Random Distributions** — Add Gaussian, log-normal, uniform, and other distributions actually required by valuation assumptions.

### Story — Seeded Samples

**Library: GNU GSL RNG** — Produce deterministic random streams from an explicit valuation seed.

### Story — Distribution Samples

**Library: GNU GSL Random Distributions** — Produce sampled growth, margin, WACC, ROIC, or other selected assumptions from configured distributions.

### Story — Bound Samples

**Library: Apache Arrow Compute** — Apply hard methodology constraints to sampled values using backend comparisons and conditional selection.

## Epic 3.2 — Monte Carlo Valuation Runner

Evaluate thousands of sampled input sets through the unchanged deterministic valuation function.

### Story — Integrate Simulation Runner

**Library: GSL RNG/Distributions + existing Yamori valuation pipeline** — Connect sampled assumption generation to repeated deterministic valuation calls.

### Story — Generate Input Matrix

**Library: GSL Random Distributions + Arrow Arrays** — Materialize N sampled assumption sets in columnar form.

### Story — Run Valuation Samples

**Library: Existing Yamori valuation pipeline** — Evaluate each generated assumption set without adding Monte Carlo-specific valuation formulas.

### Story — Invalid Sample Handling

**Library: Yamori orchestration** — Record constraint failures or mathematically invalid valuations without replacing backend mathematics.

## Epic 3.3 — Monte Carlo Summary

Convert sampled intrinsic values into the uncertainty summary required by the valuation output.

### Story — Integrate GSL Simulation Statistics

**Library: GNU GSL Statistics** — Use GSL for distribution summaries and percentile calculations.

### Story — Mean and Dispersion

**Library: GNU GSL Statistics** — Calculate mean and standard deviation of simulated intrinsic values.

### Story — Median and Percentiles

**Library: GNU GSL Statistics** — Calculate P5/P25/P50/P75/P95 or the final agreed percentile set.

### Story — Valuation Range

**Library: GNU GSL Statistics** — Derive the displayed valuation range from configured percentiles.

### Story — Reproducibility Test

**Library: GSL RNG + existing pipeline** — Prove identical input, backend versions, seed, and sample count produce the same simulation output.

## Epic 3.4 — Monte Carlo Demo

Run CSV → deterministic DCF → Monte Carlo distribution in one executable flow.

### Story — Integrate Monte Carlo Pipeline

**Library: Arrow CSV + Arrow Compute + GSL Statistics/Interpolation/Roots/RNG/Distributions** — Assemble the complete Milestone 1–3 stack without introducing another math implementation.

### Story — Base-case Preservation

**Library: Existing Yamori valuation pipeline** — Prove enabling simulation does not change the deterministic base valuation.

### Story — Distribution Output

**Library: GNU GSL Statistics** — Emit base value, mean, median, percentiles, dispersion, and valuation range.

---

# Milestone 4 — Runtime Unification

Only after the valuation functionality is proven, refactor the loose backend integrations into Yamori's durable build, C ABI, routing, and common memory representation.

## Epic 4.1 — Unified Arrow Memory Model

Make Arrow-compatible buffers the canonical Yamori representation so CSV, compute, GSL adapters, and future backends can share data without unnecessary copying.

### Story — Integrate Arrow C Data Interface

**Library: Apache Arrow C Data Interface** — Establish Arrow's language-neutral array/schema representation as the interoperability substrate.

### Story — Yamori Buffer

**Library: Arrow Buffer/C Data Interface** — Wrap owned, borrowed, foreign, and eventually shared buffers without defining numerical storage independently.

### Story — Yamori Array

**Library: Arrow Array/C Data Interface** — Represent typed numeric arrays using Arrow-compatible physical memory.

### Story — Yamori Series

**Library: Arrow Array/Schema** — Add name, null validity, and logical type metadata around the common representation.

### Story — Yamori Table

**Library: Arrow Table/RecordBatch** — Standardize tabular representation across CSV and compute paths.

### Story — GSL Zero-copy View

**Library: GNU GSL** — Adapt contiguous Yamori/Arrow numeric buffers into GSL views where the backend API permits.

## Epic 4.2 — Unified Backend Router

Move every direct Arrow/GSL invocation behind one stable semantic dispatch layer while preserving all previous numerical results.

### Story — Integrate Arrow Function Registry

**Library: Apache Arrow Compute** — Route Arrow-backed operations through registered function identifiers instead of scattered direct calls.

### Story — Integrate GSL Backend Adapter

**Library: GNU GSL** — Consolidate statistics, interpolation, root, RNG, and distribution access behind one backend module.

### Story — Capability Registry

**Library: Yamori orchestration** — Map each Yamori operation to its backend implementation without duplicating the implementation.

### Story — Backend Error Translation

**Library: Arrow Status + GSL error codes** — Normalize backend failures into Yamori statuses.

### Story — Backend Type Isolation

**Library: Yamori orchestration** — Prevent C++ Arrow and GSL implementation types from leaking through Yamori's public surface.

## Epic 4.3 — Shared-memory Representation

Allow the same financial arrays and tables to be mapped by multiple processes while retaining Arrow-compatible layout.

### Story — Integrate Arrow Shared-buffer Representation

**Library: Apache Arrow memory layout** — Base cross-process column representation on Arrow-compatible value and validity buffers.

### Story — Offset-based Buffer Descriptor

**Library: Yamori orchestration over Arrow layout** — Store workspace-relative offsets rather than process-local pointers.

### Story — Shared Array Descriptor

**Library: Arrow-compatible layout** — Describe datatype, shape, strides, buffer offset, and validity state independently of mapping address.

### Story — Shared Table Descriptor

**Library: Arrow-compatible schema/layout** — Represent financial tables as shared schemas plus offset-addressed column buffers.

### Story — Zero-copy Process Attach

**Library: OS shared-memory APIs + Arrow-compatible layout** — Map an existing Yamori dataset into another process without serializing numeric contents.

## Epic 4.4 — C ABI

Freeze a language-neutral interface only after the semantics have been proven by the first three milestones.

### Story — Integrate Arrow C ABI Types

**Library: Apache Arrow C Data Interface** — Use Arrow's existing C ABI structures for array/table interchange instead of inventing equivalents.

### Story — Yamori Status ABI

**Library: Yamori adapter** — Expose normalized backend status/error information as stable C types.

### Story — Yamori Function ABI

**Library: Existing Arrow/GSL adapters** — Export the proven Milestone 1–3 capabilities through C-callable functions.

### Story — Opaque State Handles

**Library: Yamori adapter** — Expose backend state such as solvers or RNGs through opaque handles rather than backend structures.

### Story — ABI Compatibility Tests

**Library: ABI tooling + Yamori test suite** — Detect accidental binary-interface breakage across releases.

## Epic 4.5 — Unified Build

Produce one reproducible Yamori build that pins and packages all libraries actually required by the Damodaran stack.

### Story — Integrate Arrow Build

**Library: Apache Arrow C++** — Pin and reproducibly build only the Arrow components Yamori uses: core, CSV, and Compute.

### Story — Integrate GSL Build

**Library: GNU GSL** — Pin and reproducibly build the required statistics, interpolation, roots, RNG, and distribution components.

### Story — Linux Build

**Library: Arrow + GSL** — Build and run the complete golden suite on Linux.

### Story — macOS Build

**Library: Arrow + GSL** — Build and run the complete golden suite on macOS.

### Story — Windows Build

**Library: Arrow + GSL** — Build and run the complete golden suite on Windows.

## Epic 4.6 — Refactor Parity

Prove that introducing the unified runtime architecture changes integration mechanics but not valuation outputs.

### Story — Ratio Parity

**Library: Arrow Compute** — Require every Milestone 1 golden ratio to match its pre-refactor value.

### Story — DCF Parity

**Library: Arrow Compute + GSL** — Require every deterministic Milestone 2 intermediate and final output to match.

### Story — Monte Carlo Parity

**Library: GSL RNG/Statistics** — Require the seeded Milestone 3 distribution to match its pre-refactor output.

# Explicitly not in these milestones

QuantLib, Cuba, BLAS/LAPACK, technical analysis, derivatives/options libraries, generic DataFrame functionality, generic scientific computing, and other numerical domains remain out of scope until the Damodaran path is complete and the unified Yamori runtime is proven.
