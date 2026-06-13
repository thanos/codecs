# ExCodecs Native/NIF Architecture

The Rust NIF layer is the engine of ExCodecs. Every compression and
decompression operation passes through a Rustler NIF boundary into compiled
Rust code. This document describes how that boundary works, how binaries are
handled, how errors propagate, and how the system stays safe under load.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Rust NIF Design](#rust-nif-design)
- [Precompiled Distribution](#precompiled-distribution)
- [Error Mapping](#error-mapping)
- [Scheduler Considerations](#scheduler-considerations)
- [Binary Handling](#binary-handling)
- [Safety Considerations](#safety-considerations)
- [Codec Implementation Patterns](#codec-implementation-patterns)
- [NIF Call Flow](#nif-call-flow)

---

## Architecture Overview

```
  +-------------------+       +--------------------+       +-------------------+
  | Elixir Client     |       | ExCodecs.Native    |       | Rust NIF          |
  |                   |       | (Rustler module)   |       | (cdylib crate)    |
  | ExCodecs.encode(  |  --+->| zstd_compress/2    |  --+->| zstd_codec::      |
  |   :zstd, data, [] |     | snappy_compress/1  |     |   |   zstd_compress() |
  | )                 |     | blosc2_compress/7  |     |   |                   |
  +-------------------+     +--------------------+     +-------------------+
                                    |                             |
                                    | :erlang.nif_error/2        | Rust lib crates
                                    | (fallback)                  |
                                    v                             v
                              Process crash                +-------------------+
                                                           | zstd crate        |
                                                           | lz4_flex crate    |
                                                           | snap crate        |
                                                           | bzip2 crate       |
                                                           | (pure Rust blosc2)|
                                                           +-------------------+
```

The architecture has three layers:

1. **Elixir codec modules** -- Validate options, delegate to the Native module.
2. **ExCodecs.Native** -- The Rustler-generated boundary. Defines NIF function
   stubs with `:erlang.nif_error/2` fallbacks. Maps directly to Rust functions.
3. **Rust codec modules** -- Each in its own `.rs` file, calling Rust crate
   implementations and converting results into BEAM terms.

---

## Rust NIF Design

### Crate configuration

The Rust crate is a `cdylib` targeting the BEAM NIF interface:

```toml
[package]
name = "ex_codecs_native"
version = "0.1.0"
edition = "2021"
rust-version = "1.77"

[lib]
name = "ex_codecs_native"
path = "src/lib.rs"
crate-type = ["cdylib"]
```

The `cdylib` crate type produces a shared library that the BEAM can load as a
NIF. This is the only crate type Rustler supports.

### Rustler initialization

The NIF module is registered in `lib.rs` with the `rustler::init!` macro:

```rust
rustler::init!(
    "Elixir.ExCodecs.Native",
    [
        zstd_codec::zstd_compress,
        zstd_codec::zstd_decompress,
        lz4_codec::lz4_compress,
        lz4_codec::lz4_decompress,
        snappy_codec::snappy_compress,
        snappy_codec::snappy_decompress,
        bzip2_codec::bzip2_compress,
        bzip2_codec::bzip2_decompress,
        blosc2_codec::blosc2_compress,
        blosc2_codec::blosc2_decompress,
        codec_versions,
    ],
    load = load
);

fn load(_env: Env, _term: Term) -> bool {
    true
}
```

The first argument (`"Elixir.ExCodecs.Native"`) must match the Elixir module
name exactly. The second argument is the list of NIF functions exposed to the
BEAM. The `load` callback runs once when the NIF is loaded and returns `true`
to indicate success.

### Atom definitions

Atoms are defined centrally in `atoms.rs` and shared across all codec modules:

```rust
use rustler::atoms;

atoms! {
    ok,
    error,
    unsupported_codec,
    codec_unavailable,
    invalid_data,
    invalid_options,
    compression_failed,
    decompression_failed,
    nif_not_loaded,
}
```

The `atoms!` macro pre-allocates these atoms at NIF load time, avoiding
runtime atom table lookups. Each codec module imports these atoms with
`use crate::atoms` to construct return tuples.

The atoms mirror the `error_reason` type defined in `ExCodecs.Error`:

```elixir
@type error_reason ::
        :unsupported_codec
      | :codec_unavailable
      | :invalid_data
      | :invalid_options
      | :compression_failed
      | :decompression_failed
      | :nif_not_loaded
```

This one-to-one mapping ensures that NIF error atoms are always valid
`error_reason` values. If the Rust side returns an unrecognized atom, the
Elixir error mapper falls back to `:compression_failed`.

### NIF function stubs on the Elixir side

The `ExCodecs.Native` module uses Rustler to generate the actual NIF binding:

```elixir
defmodule ExCodecs.Native do
  use Rustler,
    otp_app: :ex_codecs,
    crate: :ex_codecs_native,
    mode: :release
end
```

Each function also has a fallback that executes when the NIF is not loaded:

```elixir
def zstd_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
def zstd_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)
def lz4_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
def lz4_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)
# ... etc
```

The `:erlang.nif_error/1` call raises an error at runtime when the NIF is
absent. The application startup detects this via `function_exported?/3`:

```elixir
defp nif_loaded? do
  function_exported?(ExCodecs.Native, :zstd_compress, 2)
rescue
  _ -> false
end
```

If the NIF is not loaded, all codecs are registered as unavailable rather
than causing runtime crashes.

---

## Precompiled Distribution

### The rustler_precompiled pipeline

ExCodecs uses the `rustler_precompiled` package to distribute pre-compiled
NIF binaries. This eliminates the need for a Rust compiler on the user's
machine.

The pipeline:

```
  Developer machine                     CI / Release                    User machine
+--------------------+           +-----------------------+       +------------------+
| Write Rust code    |           | Build NIF for each    |       | mix deps.get     |
| in native/         |           | target triple:        |       |                  |
|                    |  --push->  |                       |       | rustler_precompiled
| mix rustler_precompiled.       | aarch64-apple-darwin  |       | downloads the    |
|   build             |           | x86_64-apple-darwin   |       | matching .so     |
|                    |           | x86_64-linux-gnu      |       |                  |
| produces .so files  |           | x86_64-linux-musl     |       | No Rust compiler |
| for local target   |           | aarch64-linux-gnu     |       | needed           |
|                    |           | aarch64-linux-musl    |       +------------------+
+--------------------+           | x86_64-windows-msvc   |
                                 +-----------------------+
```

### Target configuration

The target triples are defined in `mix.exs`:

```elixir
defp rustler_precompiled do
  [
    targets: [
      "aarch64-apple-darwin",
      "x86_64-apple-darwin",
      "x86_64-unknown-linux-gnu",
      "x86_64-unknown-linux-musl",
      "aarch64-unknown-linux-gnu",
      "aarch64-unknown-linux-musl",
      "x86_64-pc-windows-msvc"
    ],
    mode: :release,
    nif_versions: ["2.17"]
  ]
end
```

The `nif_versions: ["2.17"]` setting specifies the NIF API version. NIF
version 2.17 corresponds to OTP 26+ and is binary-compatible with all later
OTP versions that support NIF 2.17.

### Release optimization

The `Cargo.toml` release profile is optimized for binary size and speed:

```toml
[profile.release]
opt-level = 3        # Maximum optimization
lto = true           # Link-time optimization across crates
codegen-units = 1    # Single codegen unit for better optimization
strip = true         # Strip debug symbols from binary
```

LTO (Link-Time Optimization) allows the compiler to optimize across crate
boundaries, which can significantly reduce binary size when multiple codec
implementations are linked together. The single codegen unit gives the
optimizer more context, and stripping removes unnecessary debug info.

---

## Error Mapping

### The NIF error protocol

All NIF functions return one of two tuple shapes:

```
{:ok, binary()}      -- Success
{:error, atom()}     -- Failure
```

On the Rust side, this is constructed using the pre-allocated atoms:

```rust
// Success
(atoms::ok(), Binary::new(env, output.as_slice())).encode(env)

// Failure
(atoms::error(), atoms::compression_failed()).encode(env)
```

### Error flow diagram

```
  Rust NIF                                           Elixir
+--------------------------------------------+     +---------------------------+
| match zstd::bulk::compress(data, level) {  |     |                           |
|   Ok(compressed) =>                         |     | {:ok, compressed}         |
|     (atoms::ok(), binary).encode(env)       |---> |                           |
|                                             |     |                           |
|   Err(_) =>                                |     | {:error, :compression_    |
|     (atoms::error(), atoms::compression_   |     |          failed}          |
|       _failed()).encode(env)                |---> |                           |
| }                                          |     |                           |
+--------------------------------------------+     | ExCodecs.Error.from_nif() |
                                                   |   maps atom -> %Error{}   |
                                                   +---------------------------+
```

### Mapping in detail

The Elixir `ExCodecs.Error.from_nif/2` function enriches bare NIF error atoms
with context:

```elixir
def from_nif({:error, reason}, codec) when is_atom(codec) do
  {:error, %__MODULE__{
    reason: nif_error_to_atom(reason),
    message: "NIF error in codec #{codec}: #{inspect(reason)}",
    codec: codec,
    details: reason
  }}
end

defp nif_error_to_atom(reason) when is_atom(reason), do: reason
defp nif_error_to_atom(_), do: :compression_failed
```

The `nif_error_to_atom` fallback ensures that even if the NIF returns an
unexpected atom or non-atom value, the error maps to a known reason.

### Error categories

| NIF atom               | Elixir error reason     | When it occurs                        |
|------------------------|-------------------------|---------------------------------------|
| `compression_failed`   | `:compression_failed`   | Compression algorithm returns error   |
| `decompression_failed` | `:decompression_failed` | Decompression algorithm returns error |
| `invalid_data`         | `:invalid_data`          | Input is malformed (e.g., bad header) |
| `invalid_options`      | `:invalid_options`       | Options are out of range              |

Note: option validation happens at the Elixir layer before the NIF is called.
The NIF should never receive invalid options. However, `invalid_options` is
defined as an atom for defense-in-depth.

### Which layer validates what

```
+------------------+     +------------------+     +------------------+
| ExCodecs module  |     | Codec module     |     | Rust NIF         |
| (public API)     |     | (per-algorithm)  |     | (implementation) |
+------------------+     +------------------+     +------------------+
| Validates:       |     | Validates:       |     | Validates:       |
|  - codec exists  |     |  - level ranges   |     |  - data length   |
|  - data is binary|     |  - option types   |     |  - internal      |
|  - opts is list  |     |  - option values   |     |    constraints   |
+------------------+     +------------------+     +------------------+
```

The Elixir layers handle structural validation (types, ranges). The Rust layer
handles algorithmic validation (malformed input, buffer overflows). This
separation keeps the NIF layer simple and the Elixir layer informative.

---

## Scheduler Considerations

### Why DirtyCpu?

The BEAM scheduler is designed for fine-grained, cooperative concurrency. Each
BEAM process gets a budget of "reductions" (roughly, function calls). When a
process exhausts its budget, the scheduler preempts it and runs the next
process.

A compression NIF call is not fine-grained. Compressing a 10 MB buffer with
Zstd at level 22 can take hundreds of milliseconds of continuous CPU time.
Running this on a normal scheduler thread blocks that thread from executing
other processes, causing:

- Latency spikes for GenServer calls on the same scheduler
- Timeouts in process_link monitors
- Degraded cluster throughput

The `schedule = "DirtyCpu"` annotation tells the BEAM to execute the NIF on a
dirty CPU scheduler:

```rust
#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_compress<'a>(env: Env<'a>, data: Binary, level: i32) -> Term<'a> {
```

### Dirty scheduler configuration

The BEAM creates dirty CPU schedulers based on the `-SDio` flag (default: same
as online schedulers). A typical configuration:

```
+---- Normal schedulers (1 per core) ----+
|  Scheduler 1 | Scheduler 2 | ...      |
|  (Elixir processes, OTP tasks)         |
+-----------------------------------------+

+---- Dirty CPU schedulers ----+
|  Dirty 1 | Dirty 2 | ...   |
|  (NIF calls)                |
+-----------------------------+

+---- Dirty IO schedulers ----+
|   IO 1  |   IO 2  | ...    |
|  (file, network I/O)        |
+-----------------------------+
```

All ExCodecs NIFs use `DirtyCpu` rather than `DirtyIo` because compression and
decompression are CPU-bound, not I/O-bound.

### What happens without DirtyCpu?

If a NIF is not annotated with `schedule = "DirtyCpu"`, Rustler defaults to
running it on a normal scheduler. For small inputs, this is fine. For inputs
larger than a few kilobytes, the NIF will block the scheduler thread for
potentially long periods, causing cascading latency in the BEAM.

ExCodecs annotates every compression and decompression NIF with `DirtyCpu`
because the framework cannot predict input sizes at compile time.

---

## Binary Handling

### Input: Binary (immutable, reference-counted)

Rustler provides the `Binary` type for reading BEAM binaries in Rust:

```rust
pub fn zstd_compress<'a>(env: Env<'a>, data: Binary, level: i32) -> Term<'a> {
```

`Binary` is a zero-copy reference to the BEAM's binary data. When the BEAM
passes a binary to a NIF, it does not copy the data -- it provides a pointer
to the existing binary buffer. The `Binary` type ensures the binary's
reference count is maintained for the duration of the NIF call.

Key properties:
- **Immutable**: The NIF cannot modify the input binary.
- **Zero-copy input**: No allocation or copying for the read path.
- **Slice access**: `data.as_slice()` returns a `&[u8]` view.

### Output: NewBinary (mutable, allocated)

Rustler's `NewBinary` type allocates a new BEAM binary of a known size:

```rust
let mut output = NewBinary::new(env, compressed.len());
output.as_mut_slice().copy_from_slice(&compressed);
(atoms::ok(), Binary::new(env, output.as_slice())).encode(env)
```

This is a two-step process:

1. **Allocate**: `NewBinary::new(env, compressed.len())` allocates a BEAM
   binary of exactly the right size. This avoids the overhead of Erlang's
   binary append optimization (which over-allocates for growing binaries).

2. **Copy**: `output.as_mut_slice().copy_from_slice(&compressed)` copies the
   compressed data from the Rust `Vec<u8>` into the BEAM binary.

3. **Encode**: `Binary::new(env, output.as_slice())` creates an immutable
   `Binary` reference from the `NewBinary`, and `.encode(env)` converts it to
   a BEAM term.

### Binary allocation patterns across codecs

Every codec follows the same allocation pattern:

```
  +--------------+     +-----------------------+     +------------------+
  | BEAM Binary  |     | Rust Vec<u8>          |     | BEAM NewBinary   |
  | (input)      |     | (intermediate result)  |     | (output)         |
  +--------------+     +-----------------------+     +------------------+
        |                       |                            |
  Binary::from        compress/decompress          NewBinary::new(env, len)
  (zero-copy ref)     produces Vec<u8>             then copy_from_slice
        |                       |                            |
        v                       v                            v
  data.as_slice()       &compressed[..]              output.as_slice()
        |                       |                            |
        +------- ALGORITHM ------+------- copy_from_slice ---+
```

For all codecs except Blosc2, the intermediate `Vec<u8>` is the compressed or
decompressed data. For Blosc2, there is also a shuffle/unshuffle step in
between.

### Memory management

The Rust NIF has clear ownership boundaries:

- **Input `Binary`**: Owned by the BEAM. The NIF borrows it for the call
  duration. Rustler ensures the reference is valid.

- **Intermediate `Vec<u8>`**: Owned by Rust. Allocated by the compression
  crate, used for the algorithm, and then copied into the output binary.

- **Output `NewBinary`**: Owned by the BEAM. Allocated in NIF context,
  written to via `as_mut_slice()`, then converted to a BEAM term. The BEAM
  takes ownership when the NIF returns.

No Rust memory leaks are possible because all `Vec<u8>` values are dropped
when they go out of scope (Rust's ownership model). BEAM binaries are
garbage-collected normally.

---

## Safety Considerations

### No panics in NIF code

A Rust panic inside a NIF will crash the entire BEAM process that called the
NIF. This is because panics in Rust unwind the stack, and the BEAM NIF
interface does not support unwinding across the NIF boundary.

ExCodecs prevents panics through two mechanisms:

1. **Comprehensive `match` on all Results**. Every compression/decompression
   call returns a `Result`. The NIF code matches on `Ok` and `Err`, never
   calling `.unwrap()` or `.expect()`.

2. **Input validation in Elixir**. The Elixir codec modules validate all
   options before calling the NIF. This means the NIF never receives
   out-of-range values, null pointers, or empty binaries (except where
   explicitly handled).

```rust
// Safe: match on Result, never unwrap
match zstd::bulk::compress(data.as_slice(), level) {
    Ok(compressed) => {
        let mut output = NewBinary::new(env, compressed.len());
        output.as_mut_slice().copy_from_slice(&compressed);
        (atoms::ok(), Binary::new(env, output.as_slice())).encode(env)
    }
    Err(_) => (atoms::error(), atoms::compression_failed()).encode(env),
}
```

### No unsafe code

The ExCodecs Rust crate contains zero `unsafe` blocks. All memory operations
go through safe Rust abstractions:

- `Binary::as_slice()` -- safe slice access
- `NewBinary::new()` -- safe allocation
- `as_mut_slice().copy_from_slice()` -- safe copy

This is a deliberate design choice. If a codec crate requires `unsafe`, the
`unsafe` is confined to that crate's internals and is not exposed through the
ExCodecs NIF boundary.

### Resource management

All Rust resources follow the RAII (Resource Acquisition Is Initialization)
pattern. When a NIF call completes, all `Vec<u8>` buffers are dropped, all
`Binary` references are released, and the only surviving allocation is the
BEAM-owned `NewBinary` that was returned as the result.

There are no Rustler `Resource` types in ExCodecs because the codec operations
are stateless -- each call is a pure function from binary input to binary
output. There is no persistent state to manage across NIF calls.

### Integer overflow and clamping

The NIF layer clamps integer inputs to valid ranges rather than returning
errors. This is consistent with the defense-in-depth philosophy:

```rust
let level = level.clamp(1, 22);  // Zstd levels
let block_size = block_size.clamp(1, 9);  // Bzip2 block sizes
let clevel = clevel.clamp(0, 9);  // Blosc2 compression levels
```

Clamping in the NIF is a safety net. The Elixir layer validates and rejects
invalid values with informative error messages; the NIF layer clamps as a
last resort.

### Empty input handling

The Blosc2 codec explicitly handles empty input by returning a valid Blosc2
header with zero-length payload:

```rust
if data.is_empty() {
    let mut output = NewBinary::new(env, BLOSC_MIN_HEADER_LENGTH);
    // Write header with nbytes=0
    return (atoms::ok(), Binary::new(env, output.as_slice())).encode(env);
}
```

This prevents division-by-zero or buffer-underflow errors in the shuffle and
compression logic.

---

## Codec Implementation Patterns

Every codec module in Rust follows the same structure. This section shows the
pattern, then highlights differences.

### The standard pattern

```rust
use rustler::{Binary, Encoder, Env, NewBinary, Term};
use crate::atoms;

pub fn version() -> String {
    // Return the upstream crate version
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn <codec>_compress<'a>(env: Env<'a>, data: Binary, ...) -> Term<'a> {
    let /* validated/clamped params */ = ...;

    match <crate>::compress(data.as_slice(), ...) {
        Ok(compressed) => {
            let mut output = NewBinary::new(env, compressed.len());
            output.as_mut_slice().copy_from_slice(&compressed);
            (atoms::ok(), Binary::new(env, output.as_slice())).encode(env)
        }
        Err(_) => (atoms::error(), atoms::compression_failed()).encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn <codec>_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    match <crate>::decompress(data.as_slice()) {
        Ok(decompressed) => {
            let mut output = NewBinary::new(env, decompressed.len());
            output.as_mut_slice().copy_from_slice(&decompressed);
            (atoms::ok(), Binary::new(env, output.as_slice())).encode(env)
        }
        Err(_) => (atoms::error(), atoms::decompression_failed()).encode(env),
    }
}
```

### Zstd

```rust
// Uses zstd::bulk::compress for one-shot compression
// Accepts level parameter (1-22, clamped in NIF)
// Uses zstd::decode_all for decompression

#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_compress<'a>(env: Env<'a>, data: Binary, level: i32) -> Term<'a> {
    let level = level.clamp(1, 22);
    match zstd::bulk::compress(data.as_slice(), level) { ... }
}
```

### LZ4

```rust
// Uses lz4_flex::compress / lz4_flex::decompress
// lz4_flex is a pure Rust implementation (no C FFI)
// Decompression requires a max_size hint; uses data.len() * 8

#[rustler::nif(schedule = "DirtyCpu")]
pub fn lz4_decompress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    let estimated_size = data.len() * 8;
    let result = lz4_flex::decompress(data.as_slice(), estimated_size);
    ...
}
```

### Snappy

```rust
// Uses snap::raw::Encoder and snap::raw::Decoder (raw format, not framed)
// No configuration options
// Simplest codec in the set

#[rustler::nif(schedule = "DirtyCpu")]
pub fn snappy_compress<'a>(env: Env<'a>, data: Binary) -> Term<'a> {
    match snap::raw::Encoder::new().compress(data.as_slice()) { ... }
}
```

### Bzip2

```rust
// Uses bzip2::write::BzEncoder for compression (streaming API)
// Uses bzip2::read::BzDecoder for decompression (streaming API)
// Accepts block_size (1-9) and work_factor (0-250)

#[rustler::nif(schedule = "DirtyCpu")]
pub fn bzip2_compress<'a>(env: Env<'a>, data: Binary,
                          block_size: u32, _work_factor: u32) -> Term<'a> {
    let block_size = block_size.clamp(1, 9);
    // Uses std::io::Write trait for compression
    let mut writer = bzip2::write::BzEncoder::new(
        &mut compressed, bzip2::Compression::new(block_size)
    );
    writer.write_all(data.as_slice())?;
    writer.finish()?;
}
```

### Blosc2

The Blosc2 codec is the most complex. Rather than binding to the C-Blosc2
library via FFI, ExCodecs implements the Blosc2 format in pure Rust.

This approach was chosen because:

1. **No C dependency**: No system-level libblosc2 requirement. The NIF remains
   pure Rust, compilable with `rustler_precompiled`.
2. **Format control**: The header format is well-defined and simple (16 bytes).
   Parsing it in Rust is straightforward.
3. **Leverages existing Rust codecs**: The `internal_compress` and
   `internal_decompress` functions delegate to the same `lz4_flex`, `snap`,
   and `zstd` crates already used by the standalone codec NIFs.
4. **Shuffle implementation**: Byte shuffle and unshuffle are simple
   transpose operations implemented in ~30 lines of Rust.

The Blosc2 header format:

```
Offset  Size  Field
0       1     Magic byte (0x2c)
1       1     Version (2)
2       1     Flags (shuffle mode, uncompressed marker)
3       1     Reserved
4       4     nbytes (original size, little-endian u32)
8       4     cbytes (compressed size, little-endian u32)
12      1     cname (compressor code)
13      1     clevel (compression level)
14      1     shuffle (0=none, 1=byte, 2=bit)
15      1     typesize (element size in bytes)
16+     -     Payload (compressed or uncompressed data)
```

When the compressed payload is larger than the original data, Blosc2 stores
the data uncompressed with a special flags byte (`0x01`). This is handled
explicitly in the compress path:

```rust
if compressed.len() >= shuffled.len() && clevel > 0 {
    // Store uncompressed with marker flag
    flags = 0x01;
    // Copy original data directly
}
```

---

## NIF Call Flow

### Complete call flow: ExCodecs.encode(:zstd, data, level: 3)

```
 1. User calls ExCodecs.encode(:zstd, data, level: 3)
    |
 2. ExCodecs.encode/3 validates codec name exists
    |   (is_atom and is_binary guards)
    |
 3. CodecRegistry.lookup(:zstd)
    |   -> ETS lookup: {:zstd, {ExCodecs.Compression.Zstd, :compression, info}}
    |   -> {:ok, {ExCodecs.Compression.Zstd, :compression, info}}
    |
 4. Check info.module != nil
    |   -> NIF is loaded, module exists
    |
 5. validate_data(data)  -> :ok
    |
 6. ExCodecs.Compression.Zstd.encode(data, level: 3)
    |
 7. Zstd.encode validates level (1-22)
    |   -> Keyword.get(opts, :level, 3) = 3
    |   -> validate_level(3) = :ok
    |
 8. ExCodecs.Native.zstd_compress(data, 3)
    |   -> Rustler dispatches to DirtyCpu scheduler
    |
 9. Rust: zstd_codec::zstd_compress(env, data_binary, 3)
    |   -> level.clamp(1, 22) -> 3
    |   -> zstd::bulk::compress(data.as_slice(), 3)
    |   -> Ok(compressed_vec)
    |
10. Allocate BEAM binary: NewBinary::new(env, compressed_vec.len())
    |   Copy: output.as_mut_slice().copy_from_slice(&compressed_vec)
    |
11. Return: (atoms::ok(), Binary::new(env, output.as_slice())).encode(env)
    |   -> {:ok, compressed_binary}
    |
12. Result propagates back through Zstd.encode -> ExCodecs.encode
    |
13. {:ok, compressed_binary} returned to user
```

### Error call flow: ExCodecs.encode(:unknown, data)

```
 1. User calls ExCodecs.encode(:unknown, data, [])
    |
 2. CodecRegistry.lookup(:unknown)
    |   -> ETS lookup returns []
    |   -> {:error, :unsupported_codec}
    |
 3. ExCodecs.encode matches {:error, :unsupported_codec}
    |   -> {:error, Error.new(:unsupported_codec, codec: :unknown)}
    |
 4. {:error, %ExCodecs.Error{reason: :unsupported_codec, codec: :unknown}}
    |   returned to user
```

### Detailed NIF boundary flow

```
  Elixir Process                         BEAM Runtime                          Rust NIF Thread
  +------------------+                   +------------------+                  +------------------+
  | encode(:zstd,    |                   |                  |                  |                  |
  |  data, level: 3) |                   |  Dirty CPU       |                  |  zstd_compress() |
  |         |         |                   |  Scheduler       |                  |         |        |
  |         v         |                   |                  |                  |         v        |
  | Zstd.encode()    |                   |  Process waits   |    schedule=    |  level = 3       |
  | Native.zstd_     | -------- call --- |  on dirty CPU    | -- "DirtyCpu" ->|  data.as_slice()|
  |  compress(data,3)|                   |  thread to       |                  |         |        |
  |         |         |                   |  complete        |                  |         v        |
  |    ...waiting... |                   |                  |                  |  zstd::bulk::    |
  |         |         |                   |                  |                  |  compress()      |
  |         |         |                   |                  |                  |         |        |
  |         |         | <----- result --- |  Result posted   | <---- return ----|  {:ok, binary}   |
  |         v         |                   |  to process      |                  |                  |
  | {:ok, compressed} |                   +------------------+                  +------------------+
  +------------------+
```

Key observations:

- The calling process blocks until the NIF completes. This is normal for
  `DirtyCpu` NIFs -- the process is suspended and the scheduler thread is free
  to run other processes.
- The dirty CPU scheduler thread runs the NIF to completion. It does not
  participate in BEAM scheduling while the NIF is executing.
- The result is copied back to the BEAM process heap. The compressed binary is
  allocated as a BEAM refc binary and the process receives a reference to it.