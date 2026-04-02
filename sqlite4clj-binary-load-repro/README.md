# sqlite4clj bundled sqlite mismatch repro


## Problem

`sqlite4clj` appears to load its bundled native SQLite library, but the SQLite
engine actually observed at runtime does not match the bundled sqlite4clj
build.

In practice, `PRAGMA compile_options` reports flags from a different SQLite
build than the one shipped in sqlite4clj's bundled binary.

The non-bundled SQLite appears to enter the process during JVM startup via the
GTK/GIO desktop stack, which pulls in `libtinysparql`, which in turn depends on
`libsqlite3.so`.

## Theory

The bundled sqlite4clj library does appear to get loaded, but sqlite4clj uses
Coffi for symbol binding.

Specifically, this appears to be defined in Coffi's `coffi.ffi.Loader` class,
where the static `lookup` is initialized with
`Linker.nativeLinker().defaultLookup().or(SymbolLookup.loaderLookup())`.

That means Coffi searches `defaultLookup()` first and only falls back to
`loaderLookup()`, so it searches system-visible symbols before the symbols from
the explicitly loaded bundled library.

If a different `libsqlite3.so` is already present in the process by the time
sqlite4clj binds `sqlite3_*` symbols, sqlite4clj can end up calling that system
SQLite instead of its own bundled one.

## Repro

The program prints a simple verdict and then shows the expected bundled
markers alongside the related compile options it actually observed at runtime.

Run from this directory:

```bash
clojure -X:deps prep
clojure -J--enable-native-access=ALL-UNNAMED -M -m sqlite4clj-repro
```

Expected for the bundled sqlite4clj SQLite:

- `THREADSAFE=2`
- `DEFAULT_WAL_SYNCHRONOUS=1`
- `OMIT_SHARED_CACHE`
- `ENABLE_STAT4`

### Success looks like:

```text
Using sqlite4clj's bundled sqlite binaries? YES!

expected-bundled-markers:
THREADSAFE=2
DEFAULT_WAL_SYNCHRONOUS=1
OMIT_SHARED_CACHE
ENABLE_STAT4
observed-related-options:
DEFAULT_WAL_SYNCHRONOUS=1
ENABLE_STAT4
OMIT_SHARED_CACHE
THREADSAFE=2
```

### Failure looks like:

```text
Using sqlite4clj's bundled sqlite binaries? NO :(

expected-bundled-markers:
THREADSAFE=2
DEFAULT_WAL_SYNCHRONOUS=1
OMIT_SHARED_CACHE
ENABLE_STAT4
observed-related-options:
DEFAULT_WAL_SYNCHRONOUS=2
ENABLE_DBSTAT_VTAB
ENABLE_GEOPOLY
THREADSAFE=1
```
