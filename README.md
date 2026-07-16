# ExCodecs

[![CI](https://github.com/thanos/codecs/actions/workflows/ci.yml/badge.svg)](https://github.com/thanos/codecs/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/ex_codecs.svg)](https://hex.pm/packages/ex_codecs)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dt/ex_codecs.svg)](https://hex.pm/packages/ex_codecs)
[![Documentation](https://img.shields.io/badge/docs-hex.pm-blue.svg)](https://hexdocs.pm/ex_codecs)
[![License](https://img.shields.io/hexpm/l/ex_codecs.svg)](https://github.com/thanos/codecs/blob/main/LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-%7E%3E%201.17-purple.svg)](https://elixir-lang.org)
[![Coverage Status](https://coveralls.io/repos/github/thanos/codecs/badge.svg?branch=main)](https://coveralls.io/github/thanos/codecs?branch=main)

An extensible BEAM-native codec framework for Elixir.

Primary API: `ExCodecs.encode(codec, binary, opts)` / `decode/3` (registry).
`ExCodecs.Compression` is a naming alias; `ExCodecs.Spatial` holds domain
types for point clouds / Gaussians (not overloads of the registry API).

**Blosc2** produces C-Blosc2-compatible **chunks** only (not super-chunk /
B2ND / `.b2frame`). Standalone `:snappy` is separate from Blosc2 `cname:`.

## Design Philosophy

ExCodecs is not a compression library. It is a codec framework.

Compression is merely the first codec category. The architecture supports future
expansion into hashing, checksums, binary encodings, content addressing, and
streaming -- without changing the public API. Every codec implements the
`ExCodecs.Codec` behaviour and registers with the `ExCodecs.CodecRegistry` at
startup, meaning new categories slot in without touching existing code.

The `encode`/`decode` naming is category-agnostic: for compression codecs,
encoding is compressing and decoding is decompressing; for a future hash codec,
encoding would produce a digest and decoding would verify it.

## Installation

Add `ex_codecs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_codecs, "~> 0.2.0"}
  ]
end
```

Then fetch dependencies and compile:

```sh
mix deps.get && mix compile
```

Precompiled NIF binaries are available for macOS (Intel and ARM64), Linux
(x86_64 and ARM64, glibc and musl), and Windows (x86_64). They are downloaded
automatically from the [GitHub releases](https://github.com/thanos/codecs/releases)
when you run `mix deps.get`. If a precompiled artifact is not available for your
target, ExCodecs falls back to compiling the Rust NIF from source (requires
Rust 1.85+). The native crate is **pure Rust** (no C toolchain / system
compression libraries).

## Quick Start

```elixir
# Registry codecs (primary API — always codec atom + binary)
{:ok, compressed} = ExCodecs.encode(:zstd, "hello world")
{:ok, original}  = ExCodecs.decode(:zstd, compressed)
original #=> "hello world"

{:ok, compressed} = ExCodecs.encode(:zstd, my_binary, level: 9)
{:ok, compressed} = ExCodecs.encode(:blosc2, my_binary, cname: :zstd, clevel: 5, shuffle: :byte)

# Category alias for compression
{:ok, compressed} = ExCodecs.Compression.compress(:lz4, data)
{:ok, original}   = ExCodecs.Compression.decompress(:lz4, compressed)

# Discovery (registered binary codecs only)
ExCodecs.available_codecs()  #=> [:blosc2, :bzip2, :lz4, :snappy, :zstd]
ExCodecs.supports?(:zstd)    #=> true
ExCodecs.codec_info(:zstd)   #=> {:ok, %ExCodecs.Codec{name: :zstd, category: :compression, ...}}

# Spatial category (structs ↔ formats — not registry atoms)
alias ExCodecs.Spatial.{Point, PointCloud}
cloud = PointCloud.new([Point.new(0.0, 0.0, 0.0, color: {255, 0, 0})])
{:ok, ply} = ExCodecs.Spatial.encode(cloud, format: :ply)
{:ok, cloud} = ExCodecs.Spatial.decode(ply, format: :ply)
ExCodecs.Spatial.stream_decode(ply, format: :ply) |> Enum.to_list()
```

## API Overview

### Primary API (one shape)

```elixir
{:ok, encoded} = ExCodecs.encode(:zstd, binary, level: 3)
{:ok, decoded} = ExCodecs.decode(:zstd, compressed)
```

Always **codec atom + binary**. That is the original framework contract.

**Helpers (not a second protocol):**

- `ExCodecs.Compression.compress/3` — same as `encode/3` for compression codecs
- `ExCodecs.Spatial` — point clouds / Gaussians (struct ↔ format; not registry atoms)

### `encode/3` / `decode/3`

First argument is always a **codec atom**. Returns `{:ok, binary}` or
`{:error, %ExCodecs.Error{}}`.

### `available_codecs/0`

```elixir
ExCodecs.available_codecs()  #=> [:blosc2, :bzip2, :lz4, :snappy, :zstd]
```

Returns a sorted list of codec atoms that are both registered and have a
loaded native implementation.

### `supports?/1`

```elixir
ExCodecs.supports?(:zstd)       #=> true
ExCodecs.supports?(:nonexistent) #=> false
```

Returns `true` only if the codec is registered **and** its native NIF is loaded.

### `codec_info/1`

```elixir
{:ok, info} = ExCodecs.codec_info(:zstd)
info.category       #=> :compression
info.native?        #=> true
info.streaming?     #=> false  # block API only today
info.configurable?  #=> true
info.version        #=> backend version string
```

Returns a structured `%ExCodecs.Codec{}` struct with metadata, or
`{:error, :unsupported_codec}`.

## Supported Codecs

| Codec     | Category    | Configurable | Streaming | Options                                        |
|-----------|-------------|--------------|-----------|------------------------------------------------|
| `:zstd`   | compression | Yes           | No         | `level` (1-22, default 3; pure-Rust backend)  |
| `:lz4`    | compression | No            | No         | -- (size-prepended `lz4_flex` blocks)         |
| `:snappy` | compression | No            | No         | --                                              |
| `:bzip2`  | compression | Yes           | No         | `block_size` (1-9, default 9)                 |
| `:blosc2` | compression | Yes           | No         | C-Blosc2 **chunk** only (not super-chunk/B2ND/`.b2frame`). `cname`: `:blosclz`/`:lz4`/`:lz4hc`/`:zstd`/`:zlib` — not `:snappy` (use codec `:snappy`). `clevel` 0-9; `shuffle`; `typesize` |

### Spatial formats

| Format            | Types                         | Notes                                              |
|-------------------|-------------------------------|----------------------------------------------------|
| `:ply`            | PointCloud / GaussianCloud    | ASCII or binary PLY; Gaussian PLY properties       |
| `:spatial_binary` | PointCloud                    | Compact little-endian `EXCP` container             |
| `:gsplat`         | GaussianCloud                 | Compact little-endian `GSPL` container             |

See [Understanding Spatial Codecs](guides/understanding_spatial_codecs.md).

## Architecture

ExCodecs is layered as follows:

1. **Public registry API** (`ExCodecs`) — `encode/3`, `decode/3`,
   `available_codecs/0`, `supports?/1`, `codec_info/1` for **binary codecs**.

2. **Codec Behaviour** (`ExCodecs.Codec`) — `encode/2` / `decode/2` on binaries;
   optional `__codec_info__/0` for registry metadata.

3. **Codec Registry** (`ExCodecs.CodecRegistry`) — ETS map of codec atoms →
   modules, populated at application startup.

4. **Native NIFs** (`ExCodecs.Native`) — pure-Rust compression via
   `rustler_precompiled` (or local compile).

5. **Category modules** — `ExCodecs.Compression` (aliases for registry codecs)
   and `ExCodecs.Spatial` (struct↔format codecs, not registry atoms).

To add a **registry** codec: implement `ExCodecs.Codec`, wire a NIF if needed,
register in `ExCodecs.Application`. Spatial formats are added under
`ExCodecs.Spatial` instead.

## Error Handling

All public functions return `{:ok, result}` or `{:error, %ExCodecs.Error{}}`.
Error reasons are atoms:

| Reason                | Meaning                                          |
|-----------------------|--------------------------------------------------|
| `:unsupported_codec`  | The codec name is not registered                 |
| `:codec_unavailable`  | Registered but the native NIF failed to load    |
| `:invalid_data`       | Data is not a binary or is otherwise invalid     |
| `:invalid_options`    | Options are out of range or malformed            |
| `:compression_failed` | The underlying compression operation failed      |
| `:decompression_failed`| The underlying decompression operation failed   |
| `:nif_not_loaded`     | The NIF library could not be loaded              |

```elixir
{:error, error} = ExCodecs.encode(:unknown, "data")
error.reason  #=> :unsupported_codec

{:error, error} = ExCodecs.encode(:zstd, "data", level: 99)
error.reason  #=> :invalid_options
```

## Benchmarking

ExCodecs includes benchmarking utilities via [benchee](https://github.com/bencheeorg/benchee).

```sh
# Run all compression benchmarks
mix benchmarks
```

Benchmarks are defined in `bench/` and run in the `:bench` environment. Results
are saved to `bench/results/` (git-ignored).

## Development

```sh
# Fetch dependencies and compile (includes NIF compilation)
mix deps.get && mix compile

# Run the full test suite
mix test

# Run tests with coverage
mix coveralls

# Run static analysis
mix credo
mix dialyzer

# Format code
mix format

# Lint Rust NIF code
mix rust.lint

# Run Rust NIF tests
mix rust.test

# Generate documentation
mix docs
```

### Requirements

- Elixir 1.17+
- Erlang/OTP 26+
- Rust 1.85+ (only required if precompiled NIFs are unavailable for your platform)

## License

Apache License, Version 2.0. See [LICENSE](LICENSE) for details.