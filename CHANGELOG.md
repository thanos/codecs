# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-07-16

### Added

- **`ExCodecs.Spatial`** — new spatial codec category for point clouds and
  Gaussian splats (pure Elixir, no rendering).
- Domain types: `Point`, `PointCloud`, `Gaussian`, `GaussianCloud`, `Bounds`,
  `Transform`, `Metadata`.
- Format codecs:
  - `:ply` — ASCII and binary PLY (XYZ / RGB / RGBA / normals / attributes,
    plus Gaussian PLY conventions)
  - `:spatial_binary` — compact `EXCP` binary point clouds
  - `:gsplat` — simple `GSPL` binary Gaussian format
- Streaming helpers: `ExCodecs.stream_decode/2`, `ExCodecs.stream_encode/2`,
  and `ExCodecs.Spatial.Stream` (materializing streams; optional `source: :file | :binary`).
- Spatial category module `ExCodecs.Spatial` (struct↔format); top-level
  `ExCodecs.encode/3` / `decode/3` remain **registry binary codecs only**
  (original framework shape). `stream_encode` / `stream_decode` on `ExCodecs`
  delegate to Spatial for convenience.
- Example datasets under `priv/examples/spatial/`.
- Guide: `guides/understanding_spatial_codecs.md`.
- Registry `unregister/1` and re-registration on registry process restart.
- Error reasons `:io_error` and `:truncated_input`.

### Changed

- **Native NIF is pure Rust** — no C compression libraries:
  - Zstd via `ruzstd` (not libzstd)
  - Bzip2 via `bzip2` + pure-Rust `libbz2-rs-sys`
  - Zlib (Blosc2 inner) via `flate2` rust backend
  - LZ4 / Snappy unchanged pure crates
- **Blosc2**: C-Blosc2-compatible **chunk** format via pure-Rust `blosc2-pure-rs`
  (`:blosclz`, `:lz4`, `:lz4hc`, `:zstd`, `:zlib` + shuffle/bitshuffle).
  Golden tests against python-blosc2 fixtures.
- Codec `streaming?` metadata set to `false` until real streaming exists.
- Removed unimplemented Zstd `:window_log` option from docs.
- NIF load checked at registration; NIF calls wrapped so `:nif_not_loaded`
  becomes `{:error, %ExCodecs.Error{}}` instead of raising.
- Safer PLY header parsing (no raise on malformed element lines / unknown types).
- Public API docs cover spatial formats alongside compression codecs.
- Test coverage threshold set to 84% while the new spatial PLY surface grows.

## [0.1.1] - 2026-06-15

### Added

- **Blosc2 bit shuffle support** — `shuffle: :bit` option for `ExCodecs.encode(:blosc2, ...)`,
  providing better compression on certain data patterns beyond the existing `:none` and `:byte`
  shuffle modes (#20).

### Fixed

- **Livebook 02** — Fixed `Jason.encode!/1` wrapping for-comprehensions in `%{}` (#21).
- **Livebook 02** — Wrapped for-comprehensions in parentheses inside map values.
- **Livebook 03** — Removed `Kino.VegaLite.new()` calls (Livebook auto-renders VegaLite pipelines).
- **Livebook 03** — Fixed `Kino.Input.select` to use keyword lists (`atom: "label"`) instead
  of maps.
- **Livebook 03** — Added `Kino.render()` wrapper for `Kino.Layout.grid()` widget.
- **Livebook 04** — Rewrote entirely: fixed broken markdown/code cell boundaries, moved
  top-level `def` calls into `defmodule` blocks, fixed `Agent.get_and_update` state
  corruption (was replacing struct with bare map), added `Kino`/`kino_vega_lite` deps.
- **Livebook 05** — Added `kino_vega_lite` dep for proper VegaLite rendering.

### Changed

- All livebooks now use **conditional Mix.install** setup cells that detect whether the
  project is being run locally (from the repo) or published (from Hex.pm). Local
  development uses `path:` deps with `rustler` and `force_build`; published livebooks
  use `{:ex_codecs, "~> 0.1.1"}` with pre-compiled NIFs.
- README badges updated with CI, Hex.pm, docs, license, Elixir version, and Coveralls
  coverage links.

## [0.1.0] - 2025-06-09

### Added

- Initial release of ExCodecs.
- Unified `encode/3` and `decode/3` API across all codecs.
- Codec registry with `available_codecs/0`, `supports?/1`, `codec_info/1`.
- Five compression codecs: Zstd, LZ4, Snappy, Bzip2, Blosc2.
- Blosc2 shuffle support (`:none`, `:byte`).
- Rust NIF implementation via `rustler_precompiled`.
- Precompiled binaries for macOS (ARM64, x86_64), Linux (glibc, musl, ARM64), Windows (x86_64).
- `ExCodecs.Compression` convenience module (`compress/2`, `decompress/2`).
- Structured error handling with `%ExCodecs.Error{}`.
- 154 tests (unit + property-based with StreamData).
- 90%+ test coverage.
- CI pipeline (test matrix, lint, coverage, docs).
- Release workflow for Hex.pm publishing with precompiled NIFs.
- Five livebooks: introduction, fundamentals, comparison, storage systems, Zarr workloads.
- Eleven guides covering all public modules and API details.
- Benchmarks via benchee.
- Credo and Dialyzer integration.