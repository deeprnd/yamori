Yes. The useful way to think about this is: **the market already has most of these capabilities individually; it does not have a single contract that preserves them while moving financial data through heterogeneous numerical and finance engines.**

That distinction matters. If Yamori merely says “Arrow already has nulls, so Yamori has nulls,” there is no value. If it says “the same financial series can move from Arrow Compute to GSL to TA-Lib to QuantLib with the same ownership, missing-value, provenance and reproducibility semantics,” there may be substantial value.

| Capability | Already exists somewhere? | Potential Yamori value |
|---|---:|---|
| Zero-copy arrays/tables | Yes, strongly | Make non-Arrow quant engines participate |
| Null semantics | Yes, Arrow/Polars | One finance-specific policy across all engines |
| Financial dependency graph | Not in these underlying libs | **High** |
| Provenance | Pieces exist | **High for valuation/audit** |
| Determinism policy | Individual pieces exist | **High, but hard** |
| Cross-platform packaging | Per-project | **Useful operationally** |
| Stable C ABI | Pieces exist | Unified compute/finance ABI |
| Shared memory | Arrow already strong | Moderate unless finance-aware |
| Research → production parity | Partially | **High if genuinely same runtime** |

## One zero-copy financial Series/Table representation

What this means is that Yamori chooses one canonical physical representation for data—probably Arrow-compatible buffers—and all other engines consume views of that memory.

Suppose you have:

```text
Revenue     [100, 110, 125, 140]
EBIT        [ 10,  12,  15,  18]
TaxRate     [.20, .21, .21, .22]
```

You do **not** want:

```text
Arrow buffers
   ↓ copy
GSL vectors
   ↓ copy
TA-Lib arrays
   ↓ copy
QuantLib-specific objects
```

You want:

```text
                  one values buffer
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
   Arrow Array       GSL view        TA-Lib input
```

Arrow already provides the strongest part of this story. Its C Data Interface exists specifically to exchange columnar data through a C ABI without copying, and Polars already interoperates with Arrow this way. [Apache Arrow](https://arrow.apache.org/blog/2020/05/03/introducing-arrow-c-data-interface/?utm_source=chatgpt.com)

GSL also helps because it can construct non-owning vector views directly over ordinary arrays rather than requiring its own allocation. [GNU](https://www.gnu.org/software/gsl/doc/html/vectors.html?utm_source=chatgpt.com) TA-Lib similarly processes complete C arrays. [TA-Lib.org](https://ta-lib.org/api/?utm_source=chatgpt.com)

So what is missing?

**Nobody coordinates those representations for you.**

Arrow doesn't know that a buffer is `Revenue`, that GSL should receive only valid observations, that TA-Lib output corresponds to particular dates, or that the result later feeds a valuation formula.

This becomes valuable when Yamori guarantees:

```text
Series<f64>
├── data
├── validity
├── periods
├── units
├── provenance
└── ownership
```

and adapters make that one object usable across engines.

This is not especially valuable if Yamori only ever uses Arrow. It becomes valuable when there are several heterogeneous backends.

---

## Consistent null/missing-data semantics

This sounds boring, but financial data makes it important.

These are not equivalent:

```text
Revenue = 0
Revenue = missing
Revenue = not reported
Revenue = not applicable
Revenue = NaN because calculation failed
```

Arrow has an explicit solution for physical nulls: each array can have a validity bitmap independent of the value buffer. [Apache Arrow](https://arrow.apache.org/docs/dev/format/Columnar.html?utm_source=chatgpt.com)

But numerical libraries generally operate on numbers.

A GSL vector is fundamentally:

```text
pointer
length
stride
```

There is no Arrow-style validity bitmap in that abstraction. [GNU](https://www.gnu.org/software/gsl/doc/html/vectors.html?utm_source=chatgpt.com)

TA-Lib takes arrays and has its own conventions around input/output ranges. QuantLib has its own object semantics.

So if you directly combine libraries, the application has to repeatedly decide:

```text
Does null become NaN?
Do we remove missing observations before GSL?
Does an aggregate skip them?
Does P/E become null when EPS is zero?
Does a missing debt value mean zero debt?
```

Those decisions easily become inconsistent.

Yamori could define one policy such as:

```text
missing source value
    → null

mathematically undefined
    → null + diagnostic

valid IEEE NaN source
    → NaN

0
    → actual zero
```

and then adapt each backend to that policy.

That matters because **zero and missing are radically different in financial statements**.

Again, Arrow already gives Yamori the underlying mechanism. The added value is enforcing the same semantics when leaving Arrow.

Polars illustrates why this cannot simply be assumed: it uses Arrow-like storage but documents its own particular behavior for NaNs, signed zero, equality, and floating-point results. [Polars User Guide](https://docs.pola.rs/user-guide/concepts/data-types-and-structures/?utm_source=chatgpt.com)

---

## Financial formula dependency graphs

This is, in my view, the strongest potential Yamori feature.

The underlying libraries understand operations:

```text
divide(a, b)
multiply(a, b)
median(x)
solve(f)
```

They do **not** understand finance.

Yamori can know:

```text
BookValuePerShare
    └── Equity / SharesOutstanding

P/E
    └── Price / EPS

NOPAT
    ├── EBIT
    └── TaxRate

ROIC
    ├── NOPAT
    └── InvestedCapital

FundamentalGrowth
    ├── ROIC
    └── ReinvestmentRate

IntrinsicValue
    └── ...
```

That creates a graph:

```text
Revenue ──────────────┐
                      ▼
                  EBIT Margin
                      │
EBIT ──────┐          │
           ▼          │
         NOPAT        │
           │          │
Capital ───┴─► ROIC   │
              │       │
Reinvestment ─┴─► Growth
                    │
                    ▼
                  FCFF
                    │
                    ▼
               Intrinsic Value
```

Arrow can execute operations inside that graph.

GSL can solve nodes requiring numerical methods.

QuantLib could eventually price an option node.

But **none of those libraries owns the graph**.

This yields practical capabilities almost for free:

```text
change tax rate
   ↓
invalidate NOPAT
   ↓
invalidate ROIC
   ↓
invalidate growth
   ↓
invalidate FCFF
   ↓
recalculate valuation
```

Sensitivity becomes graph reevaluation.

Monte Carlo becomes graph reevaluation with sampled inputs.

Reverse DCF becomes solving over one graph input.

Audit becomes traversing the graph backwards.

This is substantially more defensible than wrappers.

Polars has expression/query graphs, but they describe data-processing execution, not financial meaning. QuantLib has rich pricing object graphs, but it isn't a financial-statement/fundamental-valuation dependency engine.

---

## Consistent provenance

A professional valuation should be able to answer:

```text
Where did this number come from?
```

not just:

```text
What is this number?
```

For example:

```text
ROIC = 14.3%
```

should potentially carry:

```text
ROIC
├── formula: NOPAT / InvestedCapital
├── NOPAT
│   ├── EBIT
│   │   ├── source: FY2025 10-K
│   │   └── as_of: 2025-12-31
│   └── tax rate
│       └── source: FY2025 10-K
│
└── InvestedCapital
    ├── debt
    ├── equity
    ├── cash
    └── adjustments
```

And then:

```text
IntrinsicValue
└── all of the above
```

Arrow can carry metadata, but Arrow does not define a financial lineage system.

GSL doesn't know where a number came from.

TA-Lib doesn't know where a price observation came from.

QuantLib cares about financial objects and market inputs, but it does not provide a universal lineage model spanning source documents, raw statements, derived ratios, technical data and other external engines.

The value is auditability:

```text
$48.31/share
    ↓
why?
    ↓
FCFF forecast
    ↓
growth = 7.2%
    ↓
ROIC = ...
    ↓
EBIT = ...
    ↓
source document + date
```

For fundamental research this is much more useful than merely returning `48.31`.

It also allows you to distinguish:

```text
sourced input
calculated value
policy assumption
derived estimate
Monte Carlo sample
```

That is not a numerical-library concern, so the underlying libraries do not solve it.

---

## Deterministic execution

There are several levels of determinism and they should not be conflated.

The easy level is:

```text
same inputs
same formula
same algorithm
same seed
```

GSL, for example, documents that using the same RNG and seed generates the same random stream across runs. [GNU](https://www.gnu.org/software/gsl/doc/html/rng.html?utm_source=chatgpt.com)

The harder level is:

```text
same results across
Linux x86
Linux ARM
macOS ARM
Windows x86
```

including floating-point results.

A wrapper **cannot magically guarantee that**.

Different backends may use different SIMD implementations, reduction orders, compiler behavior or math functions. Polars, for example, explicitly states that it does not generally guarantee particular floating-point error behavior or preservation of all NaN/zero details. [Polars User Guide](https://docs.pola.rs/user-guide/concepts/data-types-and-structures/?utm_source=chatgpt.com)

So if Yamori wants determinism as a feature, it needs an execution policy:

```text
backend version pinned
algorithm pinned
RNG pinned
seed explicit
threading policy pinned
reduction order specified where necessary
fast-math disabled where necessary
CPU-specific paths controlled where necessary
```

and then extensive golden testing.

This is potentially valuable because the individual libraries generally optimize for **correct/high-performance computation**, not for ensuring that a valuation produced on an ARM Mac exactly reproduces a result from a Windows x86 machine.

But this is also one of the hardest claims Yamori could make.

I would initially promise:

> reproducible algorithm/configuration and numerically equivalent results

before promising universal bit identity.

---

## Cross-platform packaging of difficult native dependencies

This is operational rather than mathematical value, but it can be substantial.

Consider what an application might otherwise have to build:

```text
Arrow C++
GSL
TA-Lib
QuantLib
BLAS
Cuba
...
```

Each has its own:

```text
CMake/autotools/build system
compiler requirements
features
transitive dependencies
Windows behavior
macOS behavior
Linux packaging
```

Arrow alone has separate build switches for Compute, CSV, IPC, compression codecs and other components. [Apache Arrow](https://arrow.apache.org/docs/dev/developers/cpp/building.html?utm_source=chatgpt.com)

QuantLib's site currently notes official binary distributions for Python, while native C++ users generally rely on source builds or third-party package managers rather than a single official binary package for every platform. [quantlib.org](https://www.quantlib.org/download.shtml?utm_source=chatgpt.com)

If Yamori can offer:

```text
libyamori.so
libyamori.dylib
yamori.dll
```

with a tested combination of:

```text
Arrow version X
GSL version Y
TA-Lib version Z
QuantLib version Q
```

that removes real engineering work.

This is similar to why Python scientific distributions historically had value: not necessarily because they invented every algorithm, but because they made a compatible ecosystem installable.

The weakness is that this is expensive maintenance and by itself isn't a strong intellectual differentiation.

---

## A stable C ABI usable from many languages

Some underlying libraries already have excellent C interfaces.

GSL is C.

TA-Lib has a C API. [TA-Lib.org](https://ta-lib.org/api/?utm_source=chatgpt.com)

Others don't expose their useful functionality through a clean C ABI.

Arrow's **data** interoperability is excellent through the C Data Interface, but Arrow Compute itself is primarily C++. [Apache Arrow](https://arrow.apache.org/blog/2020/05/03/introducing-arrow-c-data-interface/?utm_source=chatgpt.com)

QuantLib is a C++ framework; its project provides bindings to multiple other languages around that C++ object model. [quantlib.org](https://www.quantlib.org/?utm_source=chatgpt.com)

NumPy demonstrates the opposite model: its C API is deeply tied to Python objects such as `PyArrayObject` and requires initialization of the NumPy/Python API. [NumPy](https://numpy.org/devdocs/reference/c-api/types-and-structures.html?utm_source=chatgpt.com)

Yamori could establish:

```c
ym_series_pe(...)
ym_stats_median(...)
ym_valuation_dcf(...)
ym_ta_macd(...)
ym_options_implied_vol(...)
```

with arrays exchanged via Arrow C structs.

Then:

```text
Python ─┐
Rust ───┤
Zig ────┼── Yamori ABI ── heterogeneous backends
Go ─────┤
C# ─────┤
Java ───┘
```

The value is not that C ABIs are novel.

It's that **one ABI covers domains whose underlying implementations currently expose unrelated APIs and language models**.

This becomes particularly valuable if the ABI remains stable when you replace:

```text
GSL implementation
Arrow version
QuantLib version
```

underneath.

---

## Shared-memory interoperability

This one needs qualification because **Arrow already solves a large portion of it**.

Arrow IPC data can be memory-mapped, and Arrow documents zero-copy access when the underlying source permits it. [Apache Arrow](https://arrow.apache.org/docs/dev/cpp/ipc.html?utm_source=chatgpt.com) Arrow explicitly lists local cross-language/process memory sharing as a use case. [Apache Arrow](https://arrow.apache.org/use_cases/?utm_source=chatgpt.com)

So “Yamori supports shared memory” alone is not differentiating.

Where Yamori might add value is making the shared object semantically useful to financial consumers.

Instead of merely:

```text
Arrow RecordBatch
```

you might have:

```text
FinancialFrame
├── symbol: STLA
├── frequency: Quarterly
├── currency: EUR
├── periods
├── metrics
├── units
├── validity
├── provenance
└── Arrow buffers
```

Then a Tickoni tile can publish it and another process can attach without serializing all of the data.

More importantly, the receiving process understands that column X is:

```text
EBIT
unit: EUR
periodicity: FY
source: filing
```

rather than merely:

```text
float64 column called "EBIT"
```

That semantic layer is where Yamori could add value.

If you don't add that, Arrow IPC alone probably solves the problem adequately.

---

## Research → production parity

This is potentially a very strong reason for Yamori.

The common finance workflow is:

```text
research
Python
├── NumPy
├── pandas
├── SciPy
└── assorted packages

             ↓ rewrite

production
C++ / Rust / Java / Zig
```

That creates two implementations.

Even when the production system uses some of the same underlying libraries, orchestration and semantics may differ.

With Yamori:

```text
Python notebook
      │
      ▼
   Yamori
      ▲
      │
production application
```

Python:

```python
yamori.valuation.dcf(...)
```

and Zig:

```zig
yamori.valuation.dcf(...)
```

could call the **same native function**, same dependency graph and same backend versions.

That removes a whole category of problems:

```text
Python formula differs subtly from production formula
different missing-value behavior
different interpolation method
different RNG
different options model
different data conversions
```

QuantLib already demonstrates this benefit within its own domain: its C++ framework is exported to languages including Python, C#, Java and R. [quantlib.org](https://www.quantlib.org/?utm_source=chatgpt.com)

Yamori's proposed difference is doing it **across several quantitative domains simultaneously**.

If the Python interface is merely a reimplementation of the Zig API in Python, there is little value.

If both are thin frontends to the exact same runtime, the value is real.

---

## So what is actually missing?

The ecosystem already has:

```text
Arrow
→ excellent cross-language columnar memory

Polars
→ excellent DataFrame execution

GSL
→ mature numerical algorithms

TA-Lib
→ technical analytics

QuantLib
→ deep financial instrument pricing

NumPy/SciPy
→ excellent Python scientific computing
```

What it does **not give you automatically** is:

```text
financial semantics
       +
shared data representation
       +
formula lineage
       +
provenance
       +
one execution policy
       +
one deployment
       +
one ABI
```

across all of those domains.

That is the plausible Yamori gap.

And I would rank the proposed advantages like this conceptually:

**Financial dependency graph + provenance** is the strongest potential differentiation.

**Research→production parity + unified ABI + packaging** is strong practical value.

**Consistent missing-data and deterministic execution policy** can become important infrastructure value.

**Zero-copy and shared memory by themselves are not differentiation**, because Arrow and ecosystems such as Polars already do them very well. Yamori should build on those rather than claim them as inventions. [Polars User Guide](https://docs.pola.rs/user-guide/misc/arrow/?utm_source=chatgpt.com)

So if Yamori is going to deserve its own project, I would increasingly define it as:

> **A native financial computation runtime that gives financial meaning, lineage, reproducibility and a common execution contract to best-in-class quantitative engines.**

That is stronger—and more accurate—than simply “one wrapper for quant libraries.”
