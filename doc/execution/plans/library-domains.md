I’d sequence Yamori by **domain capability**, introducing a library only when a domain actually needs it. The current Damodaran prompt already defines the first core domains: ratios/history, WACC, ROIC/reinvestment, staged growth, FCFF, terminal value, reverse DCF, sensitivity, and Monte Carlo. prompt prompt

## 1. Tabular financial data & ratio calculation — Apache Arrow

**Introduce:** Milestone 1, first dependency.

**Domain:** financial statements, ratios, period series, CSV processing.

**Library:** Apache Arrow C++: Core + CSV + Compute.

**Values/capabilities:**

| Area | Values produced |
|---|---|
| Per-share | Book value/share, revenue/share, FCF/share, cash/share |
| Multiples | P/E, P/B, P/S, EV/EBIT, EV/EBITDA |
| Margins | Gross, EBIT, EBITDA, net income, FCF |
| Returns | ROIC, ROE, ROA |
| Leverage | Debt/equity, debt/capital, net debt/EBITDA |
| Growth | YoY growth, percentage change, CAGR |
| Arithmetic | `+ - × ÷`, powers, comparisons, masks |
| Aggregations | sum, mean, min/max, variance, stddev, quantiles |
| Series | shift, difference, cumulative operations |
| I/O | CSV → table → calculated columns → CSV |

Arrow should remain Yamori's **default column execution engine**.

Conceptually:

```text
CSV
 ↓
Arrow Table
 ↓
Arrow Compute
 ↓
financial ratios
 ↓
Arrow Table
 ↓
CSV
```

---

## 2. Deterministic valuation mathematics — GNU GSL

**Introduce:** Milestone 2.

**Domain:** statistical selection, interpolation, root solving, general numerical algorithms.

Arrow still performs ordinary arithmetic. GSL handles algorithms that shouldn't be implemented by Yamori.

### Statistics

**Values produced:**

```text
historical median ROIC
historical median reinvestment
historical median margins
standard deviation
variance
percentiles
outlier reference statistics
```

This directly supports the methodology's use of historical medians and outlier filtering for sustainable ROIC/reinvestment. prompt

### Interpolation

**Values produced:**

```text
Year 6–10 growth path
Year 6–10 ROIC path
Year 6–10 tax-rate path
other convergence schedules
```

For example:

```text
g_high
   │
Y5 ├─────────╲
   │          ╲
   │           ╲
Y11│            ─ g_stable
```

The prompt explicitly requires linear transition paths. prompt

### Root solving

**Values produced:**

```text
reverse-DCF implied growth
future implied values requiring inversion
```

Specifically:

```text
solve:

DCF(g_high) - market_price = 0
```

The methodology requires fixed-count bisection for reverse DCF. prompt

---

## 3. Corporate intrinsic valuation — Yamori formulas over Arrow + GSL

**Introduce:** Milestone 2.

This is an important distinction: **there isn't another upstream library here**.

These formulas define Yamori's domain semantics and should be compositions of Arrow/GSL primitives.

**Values produced:**

```text
NOPAT

Invested Capital

ROIC

Reinvestment
Reinvestment Rate

Fundamental Growth

Bottom-up Beta
Weighted CRP
Cost of Equity
Cost of Debt
WACC

10-year EBIT forecast
10-year NOPAT forecast
10-year Reinvestment
10-year FCFF

Discount Factors
PV of FCFF

Stable Reinvestment
FCFF_11
Terminal Value
PV Terminal Value

Operating Asset Value
Equity Value
Intrinsic Value / Share

Implied P/E
Implied P/S
Implied EV/EBITDA

Reverse DCF Growth

Sensitivity Matrix
Bull/Base/Bear/Stress values
```

For example, Yamori owns:

```text
growth = ROIC × reinvestment_rate
```

but multiplication itself belongs to Arrow.

Likewise Yamori owns:

```text
FCFF = EBIT × (1-tax) - reinvestment
```

while the numerical operations belong to Arrow. The formula is explicitly prescribed by the methodology. prompt

---

## 4. Monte Carlo & valuation uncertainty — GSL RNG + distributions

**Introduce:** Milestone 3.

**Domain:** uncertainty around the deterministic valuation.

No new dependency is necessary.

Use:

```text
GSL RNG
GSL distributions
GSL statistics
```

**Values produced:**

```text
sampled WACC
sampled ROIC
sampled margins
sampled growth
sampled reinvestment rates

N intrinsic-value simulations

mean IV
median IV
standard deviation

P5
P25
P50
P75
P95

valuation range
probability distributions
```

Architecture:

```text
GSL distributions
      ↓
sample assumptions
      ↓
existing Yamori DCF
      ↓
N intrinsic values
      ↓
GSL statistics
```

The Monte Carlo engine should **never have a separate DCF implementation**.

---

## 5. Runtime interoperability & memory — nanoarrow + Arrow IPC

**Introduce:** Milestone 4.

**Domain:** unified runtime architecture, language bindings, shared memory.

### nanoarrow

Use for:

```text
ArrowArray
ArrowSchema
ArrowArrayStream
```

and their lifecycle.

This becomes the language-neutral interchange boundary:

```text
Python
   │
Zig ─── Yamori C ABI
   │
Rust
```

### Arrow IPC

Use for:

```text
shared datasets
memory-mapped columnar data
process-to-process table representation
```

So M4 turns the loose implementation into:

```text
       Yamori API

       Yamori ABI
           │
     common memory
           │
   ┌───────┴────────┐
 Arrow             GSL
```

---

# After the four core milestones

These are the libraries I would add next, **by domain**, rather than adding them to the initial build.

## 6. Technical & market analytics — TA-Lib

**Introduce when:** Yamori starts supporting market-price analytics rather than fundamental valuation.

**Domain:** charting indicators, trading analytics, market-series indicators.

**Values produced:**

```text
SMA
EMA
WMA

Bollinger Bands

MACD
MACD Signal
MACD Histogram

RSI

ATR
ADX

Stochastic %K / %D

Momentum
ROC

OBV
MFI

Accumulation / Distribution

Beta
Correlation

Donchian Channels
Keltner Channels

VWAP / related volume metrics
```

This should be almost entirely:

```text
yamori.ta.macd(...)
        ↓
      TA-Lib
```

Yamori shouldn't implement EMA, RSI, Bollinger Bands, etc.

---

## 7. Options, implied volatility & derivatives — QuantLib

**Introduce when:** Yamori needs options or other financial instruments.

This includes two somewhat different domains.

### Options / volatility

**Values produced:**

```text
option theoretical value

implied volatility

delta
gamma
vega
theta
rho

Black-Scholes values
Black-76 values
Bachelier values

American option values
European option values
barrier option values
Asian option values
```

For example:

```text
market option price
       ↓
QuantLib implied-vol solver
       ↓
IV = 27.4%
```

This is where **IV** belongs.

### Fixed income / rates

Later QuantLib can also provide:

```text
bond price
yield
duration
convexity

zero curve
discount curve
forward curve

swap NPV
swap rate
FRA value

cap/floor price
swaption value
```

### Damodaran option dilution

Your actual valuation methodology eventually also needs this for outstanding employee options:

```text
outstanding employee options
              ↓
          QuantLib
              ↓
       fair-value claim
              ↓
       equity bridge
```

The methodology explicitly specifies Black-Scholes or binomial fair-value treatment when option-level data is available. prompt

So QuantLib is probably the **first post-M4 dependency** if full Damodaran completeness becomes the priority.

---

## 8. Portfolio analytics, factors & matrix-heavy finance — BLAS + LAPACK

**Introduce when:** Yamori moves from individual-company valuation into portfolio/risk/factor analytics.

**Domain:** matrix algebra.

Typical values:

```text
covariance matrix

correlation matrix

factor exposures

factor regression coefficients

portfolio variance

portfolio volatility

minimum-variance portfolio

PCA components

eigenvalues/eigenvectors

least-squares regression

Cholesky factor

large correlation transforms
```

Typical routing:

```text
yamori.linalg.matmul
        ↓
      BLAS

yamori.linalg.solve
        ↓
     LAPACK

yamori.linalg.svd
        ↓
     LAPACK
```

This becomes especially important for:

```text
multi-factor models
portfolio optimization
risk models
large Monte Carlo correlation matrices
```

Not for ordinary DCF.

---

## 9. Specialized multidimensional integration — Cuba

**Introduce when:** the actual financial model involves a high-dimensional expectation/integral where generic Monte Carlo sampling isn't enough.

**Domain:**

```text
multidimensional integration
adaptive Monte Carlo
quasi-Monte Carlo integration
```

Capabilities:

```text
Vegas
Suave
Divonne
Cuhre
```

Possible future uses:

```text
exotic derivatives
multi-asset expectations
complex payoff integration
model calibration integrals
high-dimensional probability calculations
```

This is different from:

```text
sample WACC
→ run DCF
```

which does not need Cuba.

---

# 10. Spectral/time-series mathematics — FFTW

**Introduce when:** there is a concrete requirement for frequency-domain analytics.

Potential values:

```text
FFT
inverse FFT

spectral density
frequency decomposition
autocorrelation acceleration
signal filtering
convolution
```

This is useful for advanced market microstructure/time-series work but should remain absent until a real feature demands it.

---

# Overall dependency roadmap

The sequence I would use is:

```text
M1
│
└── Apache Arrow
      ├── Core
      ├── CSV
      └── Compute

M2
│
├── Arrow
└── GNU GSL
      ├── Statistics
      ├── Interpolation
      └── Roots

M3
│
├── Arrow
└── GSL
      ├── RNG
      ├── Distributions
      └── Statistics

M4
│
├── Arrow
│   └── IPC
├── GSL
└── nanoarrow
      └── C Data Interface


Post-M4
│
├── TA-Lib
│     technical indicators
│
├── QuantLib
│     options / IV / fixed income / derivatives
│
├── BLAS + LAPACK
│     matrices / portfolios / factors / regression
│
├── Cuba
│     multidimensional integration
│
└── FFTW
      spectral analytics
```

The key architectural rule should remain:

> **A new dependency enters Yamori because a domain requires capabilities that the current backends do not provide—not because the library happens to be useful.**

That keeps the early Yamori stack very focused while leaving a clear path toward a genuinely broad quantitative runtime.
