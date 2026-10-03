# Yamori — Strategy & Positioning

## Executive summary

**Yamori is a native financial-computation runtime over fragmented best-in-class libraries.**

It provides one API, one ABI, one memory model, one error model, and one distribution/runtime layer across financial valuation, statistical analysis, technical indicators, portfolio analytics, derivatives pricing, and multidimensional integration.

Yamori does not attempt to replace mature numerical algorithms with new implementations. Instead, it makes established libraries behave as parts of one system.

Its strategic ambition is simple:

> **The quant library you build on, not around.**

Applications should not need to individually integrate Apache Arrow, GNU GSL, TA-Lib, QuantLib, BLAS/LAPACK, Cuba, FFTW, and other specialized engines.

They integrate Yamori once.

```text
Application
    │
    ▼
  Yamori
    │
    ├── financial formula dependency graph
    ├── valuation engine
    ├── technical analysis
    ├── portfolio analytics
    ├── derivatives pricing
    ├── advanced analytics
          │
          ▼
   best available
   native engines
```

Yamori is implemented in Zig, but **Zig is an implementation choice rather than the product boundary**.

The public interoperability boundary is a stable C ABI.

Python, Zig, Rust, Go, C/C++, Java, C#, and other languages should ultimately be able to operate against the same runtime.

---

# 1. The problem

Financial computation already has excellent libraries.

The problem is that they exist as separate islands.

```text
Apache Arrow C++
    columnar memory, CSV I/O, compute registry

GNU GSL
    statistics, interpolation, root solving, RNG

TA-Lib
    technical indicators (moving averages, oscillators, volatility, patterns)

QuantLib
    options pricing, fixed income, volatility surfaces, yield curves

BLAS / LAPACK
    vector/matrix operations, eigenvalue decomposition, SVD, solvers

Cuba
    multidimensional Monte Carlo and deterministic integration

FFTW
    fast Fourier transforms, spectral analysis
```

Each comes with its own:

```text
API
types
memory representation
ownership rules
error handling
threading model
build system
versioning
language bindings
platform peculiarities
```

A sophisticated financial application therefore ends up building its own integration layer.

```text
application
│
├── Arrow wrapper
├── GSL wrapper
├── TA-Lib wrapper
├── QuantLib wrapper
├── BLAS/LAPACK wrapper
├── Cuba wrapper
├── FFTW wrapper
│
├── conversions
├── error translation
├── lifetime management
├── build scripts
└── platform-specific packaging
```

Many organizations independently recreate some version of this infrastructure.

**Yamori exists to build that layer once.**

---

# 2. What Yamori is

Yamori is a **native quantitative runtime**.

It consists of four major pieces.

```text
             Yamori API
                 │
                 ▼
        Semantic abstraction
                 │
                 ▼
        Shared data model
                 │
                 ▼
          Backend router
                 │
        ┌────────┼────────┐
        ▼        ▼        ▼
     Arrow      GSL     TA-Lib
   QuantLib   BLAS/LAPACK   Cuba
        ...     ...        ...
```

### Semantic abstraction

Users interact with quantitative concepts rather than backend concepts.

```text
Array
Series
Table

ValuationInputs
ValuationResult

CovarianceMatrix
PortfolioWeights

OptionPrice
YieldCurve

IntegratorEstimate
```

The API expresses operations such as:

```text
array.mul()
array.cumsum()

valuation.dcf()
valuation.roic()
valuation.wacc()
valuation.fcff()
valuation.sensitivity()

ta.macd()
ta.rsi()
ta.bollinger_bands()

linalg.gemm()
linalg.svd()
linalg.cholesky()

portfolio.covariance()
portfolio.factor_model()
portfolio.optimize()

derivatives.option_price()
derivatives.implied_vol()

montecarlo.integrate()
montecarlo.simulate()

risk.bump_and_revalue()
risk.decompose()
```

Users should not need to know which underlying library performs an operation.

---

# 3. What Yamori is not

## Yamori is not another NumPy implementation

It does not exist to write another matrix multiplication, SVD, random-number generator, or special-function implementation when mature implementations already exist.

NumPy provides a highly developed homogeneous N-dimensional array model, broadcasting and vectorized universal functions for Python.

Yamori should reuse equivalent native capabilities rather than competing with decades of numerical implementation work.

---

## Yamori is not another SciPy

SciPy provides a broad collection of optimization, integration, interpolation, linear algebra, differential-equation and statistical algorithms and already delegates substantial work to optimized C, C++ and Fortran implementations.

Yamori's contribution is not a competing implementation of those algorithms.

Its contribution is making those classes of functionality available through a **runtime and ABI independent of Python** and composable with finance, time-series and columnar engines.

---

## Yamori is not another pandas

pandas is fundamentally a Python data-analysis framework centered around `Series` and `DataFrame`, labeled axes, heterogeneous columns and index alignment semantics.

Yamori does not intend to reproduce the entire pandas behavioral model.

In particular, it should avoid inheriting complexity such as implicit index alignment where that conflicts with predictable native execution.

---

## Yamori is not another Polars

Polars is an optimized DataFrame engine. Its core is written in Rust and its major strengths include query optimization, parallel execution, streaming and structured-data manipulation. It currently exposes first-class interfaces including Python and Rust.

Yamori may route tabular computation through Arrow or another suitable engine, but it is not trying to outperform Polars at being a DataFrame query engine.

DataFrames are one capability inside Yamori, not its reason for existence.

---

## Yamori is not another PyMC

PyMC is a probabilistic-programming framework focused on defining Bayesian models and performing inference, including modern MCMC methods such as HMC/NUTS and automatic differentiation through PyTensor.

Yamori's Monte Carlo scope is broader and lower-level:

```text
integration
simulation
quasi-random sequences
stochastic processes
derivatives pricing
risk
scenario generation
```

It can potentially expose probabilistic-computing backends, but it is not fundamentally a probabilistic-programming language.

---

## Yamori is not another QuantLib

QuantLib already provides a comprehensive C++ framework for modeling, trading, pricing and risk management in quantitative finance.

Yamori should use QuantLib where QuantLib is the appropriate engine.

The difference is scope and architecture.

```text
QuantLib
    options and derivatives framework
    fixed income
    volatility surfaces
    yield curves

Yamori
    financial-computation runtime
        │
        ├── financial formula dependency graph
        ├── valuation engine
        ├── technical analysis
        ├── portfolio analytics
        ├── derivatives pricing (QuantLib)
        └── advanced analytics
```

QuantLib is one backend inside Yamori, not its reason for existence.

Yamori is the composability layer that lets QuantLib coexist with the valuation engine, technical indicators, and portfolio analytics over one shared memory representation.

---

# 4. The strategic thesis

The scientific-computing ecosystem has optimized **algorithms** extremely well.

It has not produced an equally universal way to **compose native quantitative capabilities into applications**.

The dominant workflow remains roughly:

```text
Python
  │
  ├── NumPy
  ├── SciPy
  ├── pandas
  ├── PyMC
  ├── QuantLib bindings
  ├── TA-Lib bindings
  └── other packages
```

This is exceptionally productive for research.

But the Python environment is also the integration layer.

When the same quantitative capabilities need to become part of:

```text
native desktop applications
real-time terminals
low-latency services
plugins
embedded systems
multi-language infrastructure
shared-memory processing pipelines
```

the integration problem reappears.

NumPy itself illustrates this distinction: its C API is designed around NumPy/Python objects and requires NumPy API initialization inside the Python-extension environment.

Yamori moves the integration boundary underneath the language:

```text
           Python
              │
      Zig ── Yamori ── Rust
              │
          C++ / Go / ...
```

The runtime becomes the common denominator instead of Python.

---

# 5. Core positioning

The simplest positioning is:

> **Yamori is one native runtime for quantitative computing.**

A more explanatory version:

> **Yamori provides one coherent native API over best-in-class numerical, statistical, time-series, and financial libraries.**

And the strategic aspiration:

> **The only quant runtime your application should need to integrate.**

That is different from claiming that Yamori contains every algorithm itself.

It means:

```text
one integration

→ many quantitative capabilities
```

---

# 6. The fundamental architectural advantage

The strongest architectural advantage should be a combination of:

```text
ONE API
+
ONE ABI
+
ONE MEMORY MODEL
+
BACKEND ROUTING
```

Any one of these by itself is insufficient.

Together they are the product.

---

# 7. One API

The user sees a coherent namespace:

```text
yamori.array
yamori.linalg
yamori.stats
yamori.timeseries
yamori.ta
yamori.optimize
yamori.integrate
yamori.simulate
yamori.options
yamori.curves
yamori.risk
```

Instead of:

```text
cblas_*
LAPACKE_*
gsl_*
TA_*
Vegas(...)
arrow::compute::*
QuantLib::*
```

The API describes the problem rather than the implementation.

---

# 8. One ABI

Yamori exposes a stable C ABI.

Conceptually:

```c
ym_array_mul(...)
ym_array_cumsum(...)

ym_linalg_solve(...)

ym_stats_mean(...)

ym_timeseries_vwap(...)

ym_ta_macd(...)

ym_integrate_vegas(...)

ym_option_price(...)
```

Bindings should remain thin:

```text
Python
    ↓

Rust
    ↓

Zig
    ↓

C++
    ↓

      Yamori C ABI
           │
           ▼
       same runtime
```

This creates a major practical advantage:

**the implementation language of an application no longer determines its quantitative stack.**

---

# 9. One memory model

Yamori should have a common representation for numeric and columnar data.

Conceptually:

```text
Buffer
  │
  ├── Array
  │
  └── Series
        │
        └── Table
```

An array needs enough information to express:

```text
data
datatype
shape
strides
alignment
ownership
lifetime
```

Series add:

```text
validity
logical datatype
metadata
```

Tables add:

```text
schema
columns
```

For columnar data, Arrow should provide the interoperability model where practical.

Arrow defines a language-independent columnar representation and a C Data Interface specifically designed for cross-runtime, zero-copy exchange over a shared C ABI.

Therefore:

```text
                 same underlying memory

                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼

       BLAS view     TA-Lib view    Arrow view

          │             │             │
          └─────────────┼─────────────┘
                        │
                    Yamori Array
```

Backend adaptation becomes primarily a matter of constructing views rather than copying datasets.

---

# 10. Shared-memory computing

Yamori should be designed from the beginning for shared-memory applications.

For in-process interoperability, Arrow's C Data Interface is particularly useful because it enables zero-copy transfer through pointers.

Raw process pointers cannot, however, serve as the persistent representation across independent address spaces.

Cross-process Yamori structures should therefore use things such as:

```text
workspace ID
buffer offset
byte length
datatype
shape
strides
generation
```

rather than:

```text
void *
```

Conceptually:

```text
Process A
    │
    ▼
┌──────────────────────────────┐
│ shared-memory workspace      │
│                              │
│ schema                       │
│ column descriptors           │
│ validity bitmaps             │
│ value buffers                │
│ metadata                     │
└──────────────────────────────┘
    ▲
    │
Process B
```

Each process resolves offsets against its local mapping.

This creates a common data plane suitable for:

```text
market data
analytics
pricing
risk
plugins
terminals
worker processes
```

without serialization for trusted local pipelines.

Arrow itself distinguishes its pointer-based C Data Interface for in-process sharing from IPC mechanisms for process boundaries.

Yamori can provide the higher-level shared-memory abstraction needed above those primitives.

---

# 11. Backend routing

A Yamori function is a semantic operation that may be implemented by another project.

For example:

```text
yamori.linalg.gemm
       │
       └── BLAS / BLIS

yamori.linalg.svd
       │
       └── LAPACK

yamori.integrate.vegas
       │
       └── Cuba

yamori.ta.macd
       │
       └── TA-Lib

yamori.options.price
       │
       └── QuantLib

yamori.array.filter
       │
       └── Arrow Compute
```

The invocation flow is:

```text
function call
     │
     ▼
semantic validation
     │
     ▼
backend resolution
     │
     ▼
zero-copy view/adaptation
     │
     ▼
backend execution
     │
     ▼
error normalization
     │
     ▼
Yamori result
```

The user does not couple application code to a particular implementation.

---

# 12. Backend plurality

Eventually multiple engines may implement the same semantic operation.

For example:

```text
matrix multiply
│
├── OpenBLAS
├── BLIS
├── vendor BLAS
└── accelerator backend
```

Or:

```text
column operation
│
├── Arrow Compute
└── alternative vector engine
```

Selection can depend on:

```text
platform
CPU capabilities
datatype
input size
requested determinism
available accelerator
configured backend
```

The API remains unchanged.

This is a strategic advantage because Yamori becomes a **stable front end to an evolving backend ecosystem**.

---

# 13. The prototype-to-production advantage

One of Yamori's strongest potential differentiators is eliminating the usual prototype/rewrite split.

Today:

```text
research
Python + NumPy/SciPy/etc.
          │
          ▼
production rewrite
C++ / Rust / Zig
```

With Yamori:

```text
Python research
      │
      ▼
    Yamori
      ▲
      │
native production
```

Python and the production application can call the same numerical implementation.

The Python layer becomes an ergonomic interface rather than the owner of the computational architecture.

This makes it possible to test:

```text
same backend
same parameters
same seeds
same tolerances
same data representation
same algorithm version
```

in research and production.

For quantitative systems where reproducibility matters, that is a meaningful architectural advantage.

---

# 14. Competitive positioning

## Versus NumPy

NumPy should remain preferable when the problem is:

```text
interactive Python numerical computing
notebooks
scientific scripting
Python ecosystem integration
```

It is the fundamental Python numerical-array package and offers an extremely mature ndarray/ufunc ecosystem.

Yamori becomes attractive when the requirement is:

```text
same numerical runtime from multiple languages
native embedding
stable C ABI
shared-memory infrastructure
finance-specific capabilities
backend substitution
Python-independent deployment
```

The proposition is not:

> Yamori is better NumPy.

It is:

> NumPy is a Python numerical environment; Yamori is a native quantitative runtime.

---

# 15. Versus SciPy

SciPy should remain preferable for Python scientific research requiring its mature collection of algorithms.

Yamori becomes attractive when those capabilities need to coexist with:

```text
Arrow data
TA
pricing
risk
shared memory
native applications
multiple languages
```

behind one deployment and API contract.

Yamori may even eventually use some of the same underlying native libraries that SciPy uses.

The differentiator is architecture, not mathematical novelty.

---

# 16. Versus pandas

pandas should remain preferable for:

```text
exploratory analysis
notebooks
ad-hoc tabular manipulation
Python-native workflows
label-heavy data analysis
```

Yamori should be preferable where tabular data is part of a larger production quantitative pipeline:

```text
market data
      ↓
time-series analytics
      ↓
models
      ↓
valuation
      ↓
risk
```

and all stages need to share a native memory model.

Yamori should intentionally have **less behavioral magic** than pandas.

Predictability and interoperability matter more than reproducing every pandas convenience.

---

# 17. Versus Polars

Polars is probably the strongest comparison on pure systems architecture.

It already provides:

```text
native Rust core
parallelism
vectorized execution
query optimization
streaming
Arrow interoperability
multiple language interfaces
```

and is purpose-built as a high-performance DataFrame engine.

Yamori should therefore **not compete on DataFrame execution alone**.

Its scope starts where Polars stops:

```text
             Yamori
               │
     ┌─────────┼───────────────┐
     │         │               │
 tabular    numerical       financial
 compute     methods         models
     │         │               │
     ▼         ▼               ▼
   Arrow      GSL          QuantLib
   etc.       Cuba          etc.
```

If somebody only needs a DataFrame engine, Polars is likely the better tool.

If their application needs one native runtime spanning DataFrames, numerical solvers, Monte Carlo, technical analytics, valuation and risk, Yamori addresses a different problem.

---

# 18. Versus PyMC

PyMC is the stronger choice for:

```text
Bayesian model specification
posterior inference
HMC / NUTS
probabilistic programming
Python research
```

Its value comes from allowing users to describe probabilistic models and automatically perform inference.

Yamori should not attempt to reproduce this abstraction.

Instead, Yamori's stochastic layer covers reusable quantitative machinery:

```text
RNG
quasi-RNG
distributions
multidimensional integration
stochastic processes
path simulation
Monte Carlo pricing
scenario generation
risk
```

Probabilistic programming could eventually be another routed capability if an appropriate backend exists.

---

# 19. Versus specialized native libraries

This is perhaps the most important comparison.

TA-Lib already contains hundreds of technical-analysis functions and exposes native C APIs for both batch and streaming use.

QuantLib already provides extensive quantitative-finance functionality.

BLAS implementations already provide highly optimized linear algebra.

Yamori does not beat these projects by replacing them.

It makes them **composable**.

Without Yamori:

```text
application
    │
    ├── TA-Lib integration
    ├── QuantLib integration
    ├── BLAS integration
    ├── GSL integration
    └── Arrow integration
```

With Yamori:

```text
application
     │
     ▼
   Yamori
     │
     ├── TA-Lib
     ├── QuantLib
     ├── BLAS
     ├── GSL
     └── Arrow
```

That is the value proposition.

---

# 20. Why someone chooses Yamori

A user should choose Yamori when several of these are true:

```text
They need quantitative functionality outside Python.

They need the same runtime from several languages.

They need numerical + time-series + financial functionality together.

They want mature third-party implementations rather than new algorithms.

They do not want to maintain bindings to many native libraries.

They need predictable native deployment.

They care about avoiding unnecessary copies.

They operate over shared-memory pipelines.

They need a stable ABI despite changing backend versions.

They want research and production to use the same computational engines.

They need deterministic/reproducible numerical configuration.

They want one cross-platform binary dependency rather than many.
```

That is Yamori's target user.

---

# 21. Why someone should not choose Yamori

A clear positioning strategy also defines cases where Yamori is the wrong tool.

Use NumPy/SciPy directly if:

```text
everything lives in Python
and interactive scientific productivity matters most.
```

Use pandas if:

```text
the workload is primarily exploratory Python data analysis.
```

Use Polars if:

```text
the core problem is high-performance DataFrame/query execution.
```

Use PyMC if:

```text
the core problem is Bayesian probabilistic programming.
```

Use QuantLib directly if:

```text
the application only needs QuantLib
and there is no broader integration problem.
```

Use TA-Lib directly if:

```text
the application only needs technical indicators.
```

Yamori becomes worthwhile when **composition across these domains is the problem**.

---

# 22. The competitive advantage

Yamori's competitive advantage should not be described as having more functions.

Function counts are easy to copy and specialized libraries will nearly always have deeper coverage.

Its advantages are structural.

## 1. Language neutrality

```text
Python
Zig
Rust
C++
Go
Java
C#
...

     ↓

same runtime
```

No language becomes the mandatory orchestration environment.

---

## 2. Backend neutrality

Applications depend on Yamori semantics rather than backend APIs.

```text
application
     ↓
Yamori
     ↓
replaceable engines
```

Backend evolution does not require application rewrites.

---

## 3. Common memory representation

One buffer should be reusable by many engines.

```text
market data
     │
     ▼
shared Yamori representation
     │
     ├── statistics
     ├── TA
     ├── linear algebra
     ├── column compute
     └── pricing
```

This can eliminate large classes of conversion and copying.

---

## 4. Native deployment

The runtime does not require embedding Python simply to obtain quantitative functionality.

```text
application
     ↓
libyamori
```

That is important for terminals, services, plugins and other embedded environments.

---

## 5. Research-to-production continuity

```text
Python
   │
 Yamori
   │
native production
```

The orchestration language can change while the computational engine does not.

---

## 6. Curated integration

Yamori can ship and test known-compatible backend versions.

Instead of asking users to independently solve:

```text
Which BLAS?
Which Arrow?
Which QuantLib?
Which TA-Lib?
Which compiler flags?
Which runtime?
Which ABI?
Which Windows build?
```

Yamori provides a tested runtime distribution.

This is product value even when Yamori implements almost none of the underlying mathematics itself.

---

## 7. Stable semantics

Yamori can standardize questions that individual libraries answer differently:

```text
null handling
NaN behavior
ownership
errors
random seeds
tolerances
threading
determinism
date representation
datatype conversion
backend versioning
```

For professional quantitative systems, consistency across these boundaries is itself a feature.

---

# 23. Where the moat actually is

The moat is **not the wrapper code**.

Writing:

```text
yamori.ta.macd()
    → TA_MACD()
```

has almost no defensibility.

The difficult and valuable parts are:

```text
common data representation

zero-copy adaptation

stable semantic contracts

shared-memory architecture

backend routing

error normalization

deterministic execution policy

cross-platform backend builds

dependency compatibility

ABI stability

test vectors across backend upgrades

language bindings generated from one ABI
```

If Yamori becomes merely a collection of wrappers, there is little reason for it to exist.

If it becomes the **standard data plane and execution contract through which heterogeneous quantitative engines compose**, it solves a substantially harder problem.

### 23.1 Differentiator Ranking by Defensibility

Not all of Yamori's capabilities are equally defensible. The ranking matters for product focus and messaging:

| Rank | Differentiator | Defensibility | Why |
|------|---------------|---------------|-----|
| 1 | Financial dependency graph + provenance | **Strongest** | No underlying library owns the financial meaning layer. This is the only project that connects `ROIC depends on NOPAT depends on EBIT...` with auditable lineage. |
| 2 | Research→production parity + unified ABI + packaging | **Strong practical value** | Same runtime from Python to Zig to C++ with tested backend combinations. Operational value that saves real engineering work. |
| 3 | Consistent null/missing-data policy + deterministic execution | **Infrastructure value** | Important for correctness but not a primary differentiator — Arrow and Polars already handle nulls well; Yamori's value is enforcing the policy across heterogeneous backends. |
| 4 | Zero-copy and shared memory | **NOT differentiation** | Arrow and Polars already do this very well. Yamori should build on them rather than claim them as inventions. |

This ranking is reflected in the product focus: the dependency graph and provenance are what Yamori should lead with, while zero-copy/shared-memory are implementation details inherited from Arrow.

---

# 24. Product principle: own semantics, not algorithms

Yamori should follow one governing rule:

> **Own the contract. Delegate the implementation.**

Yamori owns:

```text
API
ABI
types
memory
ownership
semantics
routing
execution policy
errors
versioning
distribution
testing
```

Backends own:

```text
matrix algorithms
optimization algorithms
integration algorithms
technical indicators
financial models
pricing engines
special functions
```

Exceptions should require a concrete justification such as:

```text
no suitable upstream implementation
critical interoperability requirement
significant performance advantage
backend-independent primitive required
```

---

# 25. Product principle: composition before coverage

The objective should not initially be:

> Support 10,000 functions.

It should be:

> Make 100 important functions from ten different domains compose correctly over one representation.

For example:

```text
market prices
     │
     ▼
returns
     │
     ▼
rolling volatility
     │
     ▼
model calibration
     │
     ▼
option valuation
     │
     ▼
scenario risk
```

If those stages can operate over Yamori objects without backend-specific conversion code, the architectural thesis is working.

---

# 26. Product principle: avoid backend leakage

This is bad:

```text
yamori function
    returns gsl_vector
```

or:

```text
yamori function
    accepts QuantLib::YieldTermStructure
```

This is the desired model:

```text
Yamori Array
Yamori Curve
Yamori Instrument
Yamori Result
```

The backend representation remains private.

Otherwise Yamori becomes another dependency aggregator rather than an abstraction.

---

# 27. Product principle: native first, Python excellent

Yamori should not position itself against Python.

Python should be an important frontend.

```text
import yamori as ym

returns = ym.stats.log_returns(price)
vol = ym.timeseries.rolling_std(returns, 30)
pv = ym.options.price(...)
```

The difference is architectural:

```text
Python API
     │
     ▼
Yamori runtime
```

rather than:

```text
Python runtime
     │
     ▼
all architecture depends on Python
```

This allows Yamori to benefit from Python's research ergonomics without making Python mandatory in production.

---

# 28. Strategic wedge

The initial market wedge should probably **not** be generic scientific computing.

NumPy/SciPy are far too mature there.

The strongest wedge is:

> **Native quantitative finance and market analytics requiring multiple computational domains.**

That immediately creates demand for:

```text
arrays
statistics
linear algebra
time series
technical indicators
Monte Carlo
optimization
curves
derivatives
risk
```

No single existing runtime cleanly covers all of those while also providing a stable language-neutral C ABI and common data representation.

Finance is therefore a good proving ground for the broader architecture.

Yamori can remain domain-capable rather than domain-exclusive.

---

# 29. Strategic flywheel

If the architecture works, each additional backend increases the value of every frontend.

```text
new backend
      │
      ▼
Yamori C ABI
      │
      ├── immediately usable from Python
      ├── immediately usable from Zig
      ├── immediately usable from Rust
      └── immediately usable elsewhere
```

And each new frontend increases the value of every backend.

This creates a two-sided technical flywheel:

```text
            more backends
                 ▲
                 │
                 │
more languages ◄─┼─► more capabilities
                 │
                 ▼
        stronger common ABI
```

That is a fundamentally different ecosystem model from a language-specific package.

---

# 30. Build from the valuation outward, not the platform inward

The original instinct might be to design Yamori as a universal quant runtime from the start: every domain, every library, every capability, all at once. That approach is a trap.

The correct strategy is to start with the valuation engine — the one domain where all the pieces (dependency graphs, backends, shared memory, C ABI) are immediately useful — and let actual requirements force expansion to other domains at M4 and beyond.

The risk assessment is straightforward: if M4 restructuring doesn't produce reusable abstractions, you have still built the valuation engine and lost almost nothing. The platform emerges from proven necessity, not from advance architecture.

This is the product methodology for how Yamori evolves: build outward from valuation, not inward from an idealized platform.

---

# 31. The long-term position

The desired mental model is not:

```text
Yamori = NumPy clone
```

or:

```text
Yamori = finance library
```

It is:

```text
          Quantitative application
                   │
                   ▼
                Yamori
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
 numerical      analytics    finance
 engines         engines      engines
```

Yamori sits between applications and the fragmented native quantitative ecosystem.

It is the **portability, interoperability and composition layer**.

---

# 32. Positioning statement

For developers building quantitative applications that need numerical, statistical, time-series, simulation, financial-modeling and risk capabilities across languages and deployment environments, **Yamori is a native quantitative-computing runtime that unifies mature specialized libraries behind one stable ABI and shared data model**.

Unlike language-specific scientific stacks or individual specialized libraries, Yamori lets applications compose multiple best-in-class engines without adopting their APIs, memory models, build systems or language constraints.

---

# 32. Messaging hierarchy

### Shortest

> **One native runtime for quantitative computing.**

### GitHub description

> **A coherent native quantitative-computing runtime over best-in-class libraries.**

### README hero

> **Yamori — one runtime for quantitative computing.**

> Numerical computing, statistics, time series, simulation, technical analysis, financial modeling and risk through one native API.

### Developer-oriented

> **One API. One ABI. One memory model. Best-in-class quantitative engines underneath.**

### Aspirational

> **The quant library you build on, not around.**

### Internal north star

> **The only quantitative runtime an application should need to integrate.**

---

# 33. The test for whether Yamori deserves to exist

Yamori succeeds if an application that would otherwise contain:

```text
NumPy/SciPy-like numerical functionality
+
Arrow/Polars-like data operations
+
TA-Lib
+
Cuba
+
QuantLib
+
BLAS/LAPACK
+
custom native glue
```

can instead depend on:

```text
Yamori
```

while retaining the quality of those specialized implementations.

If users still have to understand and directly integrate all of Yamori's backends, Yamori has failed.

If they can treat the native quantitative ecosystem as **one coherent runtime**, Yamori has created something materially different from the libraries underneath it.
