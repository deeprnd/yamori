They are related, but they are **not three separate things you need to depend on**.

The clean model is:

```text
Apache Arrow
= the overall project + memory format + ecosystem

Apache Arrow C++
= the main native implementation we would actually use
  ├── arrays / tables
  ├── CSV
  ├── Compute
  ├── IPC
  └── Acero

Arrow C Data Interface
= tiny C ABI structs/spec for exchanging Arrow data
  ├── ArrowArray
  ├── ArrowSchema
  └── ArrowArrayStream

nanoarrow
= lightweight C library that helps use the C Data Interface
```

Apache Arrow itself is the umbrella project and columnar memory format. The C++ library is one implementation of that format and includes the actual compute/CSV/IPC functionality we need. [Apache Arrow](https://arrow.apache.org/overview/?utm_source=chatgpt.com)

The **Arrow C Data Interface is not a full library**. It is essentially a language-neutral ABI specification built around a few C structs, intended for zero-copy interchange between runtimes. [Apache Arrow](https://arrow.apache.org/blog/2020/05/03/introducing-arrow-c-data-interface/?utm_source=chatgpt.com)

There *is* also an official **Arrow C GLib** library, but that is a GLib-based C binding built on top of Arrow C++. We almost certainly **do not want it** for Yamori. [Apache Arrow](https://arrow.apache.org/docs/dev/implementations.html?utm_source=chatgpt.com)

So for Yamori I would simplify the terminology to:

```text
M1–M3:
Apache Arrow C++
GNU GSL

M4:
Apache Arrow C++
GNU GSL
nanoarrow
```

And the relationship is:

```text
                 Apache Arrow project
                         │
              ┌──────────┴──────────┐
              │                     │
       Arrow C++ library       Arrow format/spec
              │                     │
        CSV / Compute / IPC    C Data Interface
                                    │
                                nanoarrow
```

So when we previously said **“Apache Arrow C”**, that was imprecise. For Yamori, say either **Arrow C Data Interface** when talking about the ABI, or **nanoarrow** when talking about the lightweight C helper library.

The actual heavy dependency doing calculations remains **Apache Arrow C++**.
