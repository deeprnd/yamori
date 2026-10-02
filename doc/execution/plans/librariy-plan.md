# Yamori

**Yamori** is a native quantitative-computing runtime that provides one coherent API over fragmented best-in-class numerical, statistical, time-series, and financial libraries.

Rather than reimplementing mature algorithms, Yamori integrates established native libraries behind a stable, language-neutral C ABI. It standardizes data representation, memory ownership, error handling, numerical behavior, backend selection, and build/distribution across the stack.

The goal is to make linear algebra, statistics, optimization, Monte Carlo, technical analysis, derivatives pricing, risk analytics, and columnar computation behave as parts of a single library.

Yamori is implemented in Zig, but it is not Zig-specific. Its public interoperability boundary is a stable C ABI, allowing thin bindings for Zig, Python, Rust, Go, C/C++, Java, C#, and other languages.

## Architecture

Yamori separates three concerns:

```text
Application API
      │
      ▼
Yamori semantic layer
      │
      ├── arrays
      ├── series
      ├── tables
      ├── statistics
      ├── time series
      ├── linear algebra
      ├── optimization
      ├── integration
      ├── technical analysis
      ├── pricing
      └── risk
      │
      ▼
Backend router
      │
      ├── Arrow / Arrow Compute
      ├── BLAS / LAPACK / BLIS
      ├── GSL
      ├── Cuba
      ├── TA-Lib
      ├── QuantLib
      └── other specialized engines
```

Yamori owns the public API and common semantics. Specialized third-party libraries own the numerical implementations.

## Function model

Applications call Yamori functions rather than backend-specific APIs.

For example:

```text
ym.array.mul(a, b)
ym.array.cumsum(x)

ym.linalg.solve(a, b)
ym.linalg.svd(a)

ym.stats.mean(x)
ym.stats.correlation(x, y)

ym.timeseries.rolling_mean(x, 20)
ym.timeseries.vwap(price, volume)

ym.ta.macd(close)
ym.ta.rsi(close)

ym.integrate.vegas(...)
ym.optimize.brent(...)

ym.options.black_scholes(...)
ym.options.implied_vol(...)

ym.risk.bump_and_revalue(...)
```

The same operations are exposed through the C ABI:

```c
ym_status ym_array_mul(...);
ym_status ym_array_cumsum(...);

ym_status ym_linalg_solve(...);

ym_status ym_stats_mean(...);

ym_status ym_ta_macd(...);

ym_status ym_integrate_vegas(...);

ym_status ym_option_price(...);
```

Language bindings remain thin:

```text
Python:   yamori.linalg.solve(...)
Zig:      yamori.linalg.solve(...)
Rust:     yamori.linalg.solve(...)
C:        ym_linalg_solve(...)
```

All of them ultimately invoke the same native runtime.

## Backend routing

Each Yamori operation is mapped to the backend best suited to implement it.

For example:

```text
ym.linalg.gemm()
    │
    └── BLAS / BLIS

ym.linalg.svd()
    │
    └── LAPACK

ym.stats.distribution.*
    │
    └── GSL

ym.integrate.vegas()
    │
    └── Cuba

ym.ta.macd()
    │
    └── TA-Lib

ym.options.price()
    │
    └── QuantLib

ym.array.filter()
ym.array.sort()
ym.array.cumsum()
    │
    └── Arrow Compute
```

The routing layer hides backend-specific APIs and types:

```text
Application
    │
    ▼
ym.linalg.solve()
    │
    ▼
Yamori router
    │
    ├── validate inputs
    ├── resolve representation
    ├── select backend
    ├── construct zero-copy backend view
    ├── invoke backend
    ├── normalize errors
    └── return Yamori result
```

Backend choice is therefore an implementation detail.

Yamori can later replace:

```text
OpenBLAS → BLIS
Arrow Compute → another column engine
one QuantLib engine → another pricing backend
```

without changing application code or the public ABI.

Routing can eventually support multiple implementations for the same capability:

```text
ym.linalg.gemm()
    │
    ├── CPU / BLIS
    ├── CPU / vendor BLAS
    └── accelerator backend

ym.array.compute()
    │
    ├── Arrow Compute
    └── alternative backend
```

Backend selection may be fixed at build time, configured at runtime, or selected according to datatype, operation, data size, and platform.

## Shared memory representation

A central Yamori requirement is that different engines should operate on the same memory whenever possible.

The runtime therefore owns a minimal common representation for buffers, arrays, columns, and tables rather than allowing backend-specific containers to leak into the public API.

Conceptually:

```text
                    shared buffer
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
      ym.Array        ym.Series      Arrow column
          │              │              │
          ├──── BLAS     ├──── TA-Lib   ├──── Arrow Compute
          ├──── GSL      │              │
          └──── Cuba     └──────────────┘
```

A primitive array can be represented approximately as:

```text
Array
├── data pointer
├── length
├── datatype
├── shape
├── strides
├── alignment
├── ownership
└── release/lifetime information
```

A nullable Series adds:

```text
Series
├── Array values
├── validity bitmap
├── optional name
└── logical datatype
```

A Table is primarily:

```text
Table
├── schema
└── columns[]
      └── Series
```

For columnar data, Yamori should align with the Apache Arrow physical representation where practical:

```text
primitive column
├── value buffer
├── validity bitmap
└── metadata/schema
```

This makes zero-copy interoperability possible through the Arrow C Data Interface.

## Zero-copy backend views

Backends should generally receive a view over Yamori-owned or externally-owned data rather than requiring conversion.

For example:

```text
Yamori Array<f64>
       │
       ├── BLAS
       │     pointer + length + stride
       │
       ├── GSL
       │     gsl_vector_view
       │
       ├── TA-Lib
       │     pointer + range
       │
       └── Arrow
             ArrowArray + ArrowSchema
```

The underlying values remain in the same memory.

The desired execution path is:

```text
market data buffer
       │
       ▼
Yamori Series
       │
       ├── TA-Lib MACD
       ├── Arrow cumulative operation
       ├── BLAS calculation
       └── statistical routine
```

rather than:

```text
buffer
  ↓ copy
TA-Lib representation
  ↓ copy
Arrow representation
  ↓ copy
GSL representation
```

Copies should occur only when required by backend constraints, layout conversion, datatype conversion, ownership boundaries, or process isolation.

## Ownership

Buffers need explicit ownership semantics.

Conceptually:

```text
Owned
    Yamori allocated the memory and is responsible for freeing it.

Borrowed
    Yamori temporarily references memory owned elsewhere.

Foreign
    Memory comes from another runtime/library and carries a release callback.

Shared
    Memory belongs to a shared-memory region whose lifetime is managed externally.
```

This allows the same data model to work with:

```text
heap memory
memory-mapped files
Arrow buffers
shared-memory workspaces
foreign-language arrays
plugin memory
market-data feeds
```

without requiring different high-level APIs.

## Cross-process shared memory

For systems such as Tickoni, Yamori should also be usable over shared-memory regions.

The representation can be designed so that arrays and tables can refer to buffers by offsets inside a shared-memory workspace rather than process-local pointers.

Conceptually:

```text
shared workspace
│
├── schema / descriptors
│
├── validity bitmap
│
├── column A buffer
├── column B buffer
├── column C buffer
│
└── metadata
```

Each process maps the workspace:

```text
Producer process
      │
      ▼
shared-memory workspace
      ▲
      │
Consumer process
```

A table descriptor can therefore resolve to local pointers after mapping while the underlying representation remains process-neutral.

For example:

```text
SharedArray
├── workspace identifier
├── data offset
├── byte length
├── datatype
├── shape
├── strides
└── generation/version
```

This avoids storing raw process-specific addresses in shared structures.

Arrow-compatible layouts are useful here because columnar buffers, validity bitmaps, offsets, and schemas already map naturally onto shared-memory regions.

## Expression execution

Higher-level operations should compose lower-level functions without exposing backend mechanics.

For example:

```text
VWAP =
    cumsum(price × volume)
    ──────────────────────
       cumsum(volume)
```

can be expressed as:

```text
mul(price, volume)
        │
        ▼
cumsum(...)
        │
        ├─────────────┐
        │             │
        ▼             ▼
                  cumsum(volume)
        │             │
        └──── div ────┘
              │
              ▼
             VWAP
```

Each node can be routed independently to the appropriate backend.

Initially, Yamori can execute operations eagerly.

Later, an optional expression layer can represent:

```text
cumsum(price * volume) / cumsum(volume)
```

as an execution graph, allowing Yamori to:

```text
reuse temporary buffers
avoid unnecessary copies
fuse compatible kernels
schedule independent operations
select different backends
execute over shared memory
```

without changing the public API.

## Batch and streaming computation

Financial computing needs both historical batch processing and live incremental computation.

Yamori should expose consistent concepts for both:

```text
Batch
────────────────────────
Series → operation → Series

Streaming
────────────────────────
value → state → new value
```

For example:

```text
historical MACD
Series<f64> → MACD Series

live MACD
price → MACD state → current MACD
```

Backends such as TA-Lib can provide the underlying implementation where available.

This lets the same runtime support:

```text
research
historical analytics
backtesting
live market data
terminal indicators
valuation
risk
```

## Stable ABI

Third-party C and C++ types should never form part of the public ABI.

Yamori exposes either plain value types, Arrow-compatible structures, or opaque handles:

```c
typedef struct ym_array ym_array;
typedef struct ym_table ym_table;
typedef struct ym_curve ym_curve;
typedef struct ym_model ym_model;
typedef struct ym_instrument ym_instrument;
```

Complex backend objects remain internal.

This means Yamori can update Arrow, QuantLib, GSL, Cuba, TA-Lib, BLAS, or other dependencies without forcing downstream applications to track those APIs.

## What Yamori owns

Yamori should own as little numerical implementation as possible.

It owns:

```text
public API
C ABI
common types
memory representation
ownership model
backend routing
error normalization
dependency integration
cross-platform builds
zero-copy adapters
shared-memory descriptors
execution policy
versioning
```

It delegates:

```text
linear algebra             → BLAS / LAPACK / BLIS
numerical methods          → GSL and similar libraries
multidimensional integration → Cuba
technical analysis         → TA-Lib
financial models/pricers   → QuantLib
columnar compute           → Arrow Compute / Acero
```

The core principle is:

**Yamori does not compete with mature quantitative libraries. It makes them behave like one coherent runtime.**

## Why Yamori exists

Native quantitative computing is fragmented across specialized libraries with incompatible APIs, types, ownership models, build systems, error handling, and language bindings.

Without Yamori:

```text
application
├── Arrow integration
├── BLAS integration
├── GSL integration
├── Cuba integration
├── TA-Lib integration
├── QuantLib integration
├── conversion code
├── ownership adapters
├── build logic
└── error translation
```

With Yamori:

```text
application
     │
     ▼
   Yamori
     │
     ▼
best available native engines
```

Its value is therefore not another implementation of established algorithms.

Its value is:

```text
one API
one ABI
one memory model
one ownership model
one error model
one build
one routing layer
one quantitative runtime
```

over many specialized, mature engines.
