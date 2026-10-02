For these **four milestones**, I would keep the dependency set extremely small.

The required direct third-party libraries are essentially:

| Library | M1 | M2 | M3 | M4 | Role |
|---|---:|---:|---:|---:|---|
| **Apache Arrow C++** | ✓ | ✓ | ✓ | ✓ | CSV, arrays, nulls, vector math, reductions, table representation, IPC |
| **GNU GSL** |  | ✓ | ✓ | ✓ | Statistics, interpolation, root solving, RNG, distributions |
| **nanoarrow** |  |  |  | ✓ | Lightweight C-side Arrow ABI helpers for the final C ABI / interoperability layer |

So the final architecture can realistically be built around **three upstream projects**, with only **two** needed before the M4 refactor.

### Milestone 1 — Arrow only

```text
CSV
 ↓
Arrow CSV
 ↓
Arrow Arrays / Tables
 ↓
Arrow Compute
 ↓
ratios
 ↓
Arrow CSV
```

Arrow Compute already provides the important primitives we need: arithmetic, scalar broadcasting, comparisons, `if_else`, cumulative operations, pairwise differences and reductions. [Apache Arrow](https://arrow.apache.org/docs/dev/cpp/compute.html?utm_source=chatgpt.com)

So M1 needs:

```text
Apache Arrow C++
├── arrow
├── arrow::csv
└── arrow::compute
```

No GSL yet.

One implementation detail: your financial CSV is naturally **metric × period**, whereas Arrow prefers columns. Internally I would normalize it to:

```text
period × metric
```

so:

```text
Period    StockPrice    EPS    Equity    Shares
2025Q1       ...        ...      ...       ...
2025Q2       ...        ...      ...       ...
```

Then:

```text
P/E = StockPrice / EPS
BVPS = Equity / Shares
```

are straightforward Arrow column operations. When saving, Yamori can emit the original metric-oriented CSV shape.

---

### Milestone 2 — Arrow + GSL

Arrow remains responsible for almost all valuation arithmetic.

GSL fills the places where we need an actual numerical algorithm:

```text
Apache Arrow
────────────────────────
financial series
arithmetic
reductions
comparisons
discounting
FCFF
WACC arithmetic
DCF
terminal value
sensitivity matrices


GNU GSL
────────────────────────
median/statistics
interpolation
root solving
reverse DCF
```

GSL already covers statistics, interpolation and root finding among a much larger numerical API. [GNU](https://www.gnu.org/software//gsl/doc/latex/gsl-ref.pdf?utm_source=chatgpt.com)

So there is no need for:

```text
SciPy
BLAS
LAPACK
QuantLib
Cuba
Boost
Eigen
```

for the Damodaran deterministic milestone.

### Milestone 3 — still Arrow + GSL

We **do not need Cuba** for the Monte Carlo you described.

We're not trying to numerically integrate:

```text
∫ f(x1,...,xn) dx
```

We're doing:

```text
sample WACC
sample growth
sample margin
sample ROIC
       ↓
run deterministic DCF
       ↓
repeat N times
       ↓
valuation distribution
```

GSL already provides:

```text
RNGs
random distributions
CDFs / inverse CDFs
statistics
quasi-random sequences if wanted later
Monte Carlo facilities
```

GSL explicitly includes RNG, random distributions, quasi-random sequences, statistics and Monte Carlo integration. [GNU](https://www.gnu.org/software/gsl/doc/latex/gsl-ref.pdf?utm_source=chatgpt.com)

So:

```text
M3

GSL RNG
    ↓
GSL distributions
    ↓
sample assumptions
    ↓
M2 DCF
    ↓
GSL statistics
    ↓
P5 / P50 / P95 etc.
```

No new dependency.

---

### Milestone 4 — add nanoarrow

M4 is where I would add **nanoarrow**, not another numerical engine.

Arrow's C Data Interface is intentionally tiny and provides zero-copy interoperability through a C ABI. [Apache Arrow](https://arrow.apache.org/blog/2020/05/03/introducing-arrow-c-data-interface/?utm_source=chatgpt.com)

`nanoarrow` is Apache Arrow's lightweight C/C++ library for producing and consuming those Arrow structures. [Apache Arrow](https://arrow.apache.org/docs/dev/implementations.html?utm_source=chatgpt.com)

That fits Yamori very well:

```text
                 Yamori C ABI
                      │
                  nanoarrow
                      │
              Arrow C Data Interface
                      │
                Arrow buffers
```

instead of us manually implementing all the details of:

```c
struct ArrowArray
struct ArrowSchema
struct ArrowArrayStream
```

and their lifetime rules.

Again, that's consistent with your principle:

> don't implement infrastructure ourselves if a mature library already exists.

---

### Shared memory needs no fourth quant library

There's an important distinction here.

Arrow C Data Interface contains ordinary pointers and is intended for **same-process zero-copy exchange**, not cross-process sharing. Arrow's own documentation explicitly says this and recommends Arrow IPC for process boundaries. [Apache Arrow](https://arrow.apache.org/blog/2020/05/03/introducing-arrow-c-data-interface/?utm_source=chatgpt.com)

For M4 cross-process data:

```text
Tickoni process A
       │
       ▼
shared memory / mmap
       │
       │ Arrow IPC representation
       │
       ▼
Tickoni process B
```

Arrow IPC supports memory-mapped sources and can provide zero-copy access to underlying data buffers in suitable cases. [Apache Arrow](https://arrow.apache.org/docs/dev/cpp/ipc.html?utm_source=chatgpt.com)

So we can use:

```text
Apache Arrow
├── C++ core
├── CSV
├── Compute
├── IPC
└── C Data Interface

nanoarrow
└── lightweight C ABI handling
```

and the operating system's native shared-memory/mmap mechanism:

```text
Linux     mmap / shm
macOS     mmap / shm
Windows   file mappings
```

The OS calls are not a numerical dependency and Zig can call them directly.

---

## Final dependency picture

By the end of M4:

```text
Yamori
│
├── Apache Arrow C++
│   ├── arrays / tables
│   ├── CSV
│   ├── Compute
│   ├── IPC
│   └── C Data Interface
│
├── nanoarrow
│   └── lightweight Arrow C interoperability
│
└── GNU GSL
    ├── statistics
    ├── interpolation
    ├── root finding
    ├── RNG
    └── probability distributions
```

That's it for the scope we've defined.

I would **actively resist adding any other library before M4 is complete**.

In particular:

```text
Cuba        → not needed yet
QuantLib    → not needed
TA-Lib      → out of scope
BLAS/BLIS   → no matrix-heavy workload yet
LAPACK      → no need
FFTW        → no need
Polars      → Arrow already covers what M1 needs
pandas      → Python-only concern
PyMC        → wrong Monte Carlo abstraction
```

The particularly attractive part is that the architecture still leaves room later:

```text
                    Yamori
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
      Arrow          GSL           future
                                    │
                              ┌─────┼─────┐
                              Cuba  BLAS QuantLib
```

but **none of those future dependencies should contaminate the first Damodaran delivery path**.

So yes: for practical purposes, **M1–M3 are Arrow + GSL; M4 adds nanoarrow as the interoperability helper.**
