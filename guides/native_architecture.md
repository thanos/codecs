# Native Architecture

ExCodecs uses Rust-based NIFs (Native Implemented Functions) via Rustler for high-performance compression operations. This guide explains how the native layer works, how it integrates with the BEAM, and how precompiled distribution ensures reliability.

## Why Native Code?

Compression algorithms perform computationally intensive operations on large binary data. Pure Elixir implementations would be orders of magnitude slower than C/Rust implementations because:

- **BEAM binary overhead**: Elixir binaries are managed by the BEAM garbage collector. Large binary processing in Elixir involves frequent allocations.
- **SIMD and cache efficiency**: Rust and C compilers can auto-vectorize tight loops over byte arrays, using CPU SIMD instructions (AVX2, NEON) that are not available in BEAM.
- **Memory layout**: Rust can work with contiguous byte slices (`&[u8]`) without copying, while BEAM binaries may require copying between BEAM and native memory.
- **Algorithm implementation quality**: Libraries like `zstd`, `lz4_flex`, and `bzip2` are highly optimized with years of performance tuning.

The performance difference is significant:

| Operation      | Pure Elixir | Rust NIF  |
|---------------|-------------|-----------|
| Zstd compress  | ~5-20 MB/s  | ~300+ MB/s|
| LZ4 compress   | ~10-30 MB/s | ~500+ MB/s|
| Snappy compress| ~10-30 MB/s | ~500+ MB/s |

For production workloads, the native implementation is not optional -- it is essential.

## Rustler Integration

ExCodecs uses [Rustler](https://github.com/rusterlium/rustler) to bridge between Elixir and Rust. Rustler provides:

- **NIF generation**: Automatic generation of the NIF boilerplate from Rust function signatures.
- **Type conversion**: Safe conversion between Elixir terms and Rust types (binary to `&[u8]`, atoms, integers, etc.).
- **Error handling**: Rust `Result` types map to Elixir `{:ok, ...}` / `{:error, ...}` tuples.
- **Memory safety**: Rust's ownership model prevents buffer overflows, use-after-free, and other memory errors that are common in C NIFs.

### The Native Module

The Elixir side defines the NIF module:

```elixir
defmodule ExCodecs.Native do
  use Rustler,
    otp_app: :ex_codecs,
    crate: :ex_codecs_native,
    mode: :release

  def zstd_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
  def zstd_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)
  def lz4_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
  def lz4_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)
  # ... other NIFs
  def codec_versions, do: :erlang.nif_error(:nif_not_loaded)
  def nif_loaded?, do: not function_exported?(__MODULE__, :zstd_compress, 2)
end
```

Each function has a fallback that returns `:erlang.nif_error(:nif_not_loaded)`. If the NIF library fails to load, calling any of these functions raises an error. The `nif_loaded?/0` function checks whether the NIF has been loaded by testing if `zstd_compress/2` is still the fallback.

### The Rust Crate

The Rust crate lives in `native/ex_codecs_native/`:

```
native/ex_codecs_native/
  Cargo.toml
  src/
    lib.rs
    atoms.rs
    zstd_codec.rs
    lz4_codec.rs
    snappy_codec.rs
    bzip2_codec.rs
    blosc2_codec.rs
```

Each codec module implements the compression and decompression functions using the appropriate Rust library:

```rust
// Simplified example of zstd_codec.rs
#[rustler::nif]
fn zstd_compress(data: Binary, level: i32) -> Result<Binary, Error> {
    let compressed = zstd::encode_all(data.as_slice(), level)
        .map_err(|e| Error::new(e.to_string()))?;
    Ok(Binary::new(compressed))
}

#[rustler::nif]
fn zstd_decompress(data: Binary) -> Result<Binary, Error> {
    let decompressed = zstd::decode_all(data.as_slice())
        .map_err(|e| Error::new(e.to_string()))?;
    Ok(Binary::new(decompressed))
}
```

The `Cargo.toml` specifies the Rust crate dependencies:

```toml
[dependencies]
rustler = "0.36"
zstd = "0.13"
lz4_flex = "0.11"
snap = "1.1"
bzip2 = "0.4"
```

The release profile is optimized for performance:

```toml
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
strip = true
```

- **`opt-level = 3`**: Maximum optimization.
- **`lto = true`**: Link-Time Optimization, enabling cross-crate inlining.
- **`codegen-units = 1`**: Single codegen unit for better optimization.
- **`strip = true`**: Strip debug symbols for smaller binaries.

## DirtyCpu Scheduling

Compression NIFs are CPU-intensive and can take significant time. The BEAM scheduler has two types of NIFs:

- **Normal NIFs**: Must return quickly (under ~1 ms). If they take too long, they block the BEAM scheduler.
- **Dirty NIFs**: Long-running NIFs that are offloaded to dirty scheduler threads.

Rustler automatically marks NIFs as dirty when they are expected to take more than ~1 ms. Compression of data larger than a few kilobytes will take longer than this, so the NIFs in ExCodecs run on dirty CPU schedulers.

### BEAM Scheduler Impact

```
BEAM Scheduler Threads
+-------------------------+
| Scheduler 1  (normal)   |  Runs Elixir processes, short NIFs
| Scheduler 2  (normal)   |
| Scheduler 3  (normal)   |
| Scheduler 4  (normal)   |
+-------------------------+
| Dirty CPU 1             |  Runs ExCodecs NIFs, other CPU NIFs
| Dirty CPU 2             |
+-------------------------+
| Dirty IO 1             |  Runs I/O NIFs
+-------------------------+
```

The number of dirty CPU schedulers defaults to the number of CPU cores. You can configure this:

```elixir
# In vm.args or system flags
+SDcpu 4    # 4 dirty CPU schedulers
```

### Implications for Production

1. **Dirty NIFs do not block normal schedulers.** Your Elixir processes continue running while compression happens in the background.

2. **Concurrent compression is limited by dirty scheduler count.** If you dispatch more concurrent compression operations than dirty CPU schedulers, they will queue up.

3. **Memory is allocated outside the BEAM heap.** NIF memory allocations use the system allocator, not the BEAM allocator. Large compression buffers do not trigger BEAM garbage collection but do consume system memory.

4. **Monitors and timeouts are not possible for NIF calls.** Once a NIF starts, it runs to completion. You cannot set a timeout for a single NIF call. If you need timeouts, wrap the NIF call in a `Task` with `Task.yield/2`.

```elixir
# Timeout pattern for NIF calls
task = Task.async(fn -> ExCodecs.encode(:bzip2, large_data) end)

case Task.yield(task, 5000) || Task.shutdown(task) do
  {:ok, result} -> result
  nil -> {:error, :timeout}
end
```

## Precompiled Distribution

ExCodecs uses [`rustler_precompiled`](https://github.com/philipatrojek/rustler_precompiled) to distribute pre-built NIF binaries, eliminating the need for a Rust compiler on the target machine.

### How It Works

1. During CI/release, NIF binaries are compiled for all target platforms.
2. The binaries are attached to the Hex package or fetched from a GitHub release.
3. At application startup, Rustler loads the precompiled binary for the current platform.
4. If no precompiled binary is available, Rustler falls back to compiling from source (requires Rust toolchain).

The target platforms configured in `mix.exs`:

```elixir
defp rustler_precompiled do
  [
    targets: [
      "aarch64-apple-darwin",      # macOS ARM64
      "x86_64-apple-darwin",        # macOS x86_64
      "x86_64-unknown-linux-gnu",   # Linux x86_64 (glibc)
      "x86_64-unknown-linux-musl",  # Linux x86_64 (musl/Alpine)
      "aarch64-unknown-linux-gnu",  # Linux ARM64 (glibc)
      "aarch64-unknown-linux-musl", # Linux ARM64 (musl/Alpine)
      "x86_64-pc-windows-msvc"     # Windows x86_64
    ],
    mode: :release,
    nif_versions: ["2.17"]
  ]
end
```

### NIF Version Compatibility

The `nif_versions: ["2.17"]` field specifies the BEAM NIF API version. OTP 27+ uses NIF version 2.17. This means:

- **OTP 27+**: Full compatibility.
- **OTP 26 and earlier**: May require compiling from source or using an older precompiled binary.

Check your OTP version:

```elixir
System.otp_release()
# => "27"
```

### Benefits of Precompiled NIFs

- **No Rust toolchain required.** Users do not need to install `rustc`, `cargo`, or any Rust libraries.
- **Consistent builds.** Every platform gets the same optimized binary.
- **Fast installation.** `mix deps.get` downloads the precompiled binary; no compilation step.
- **Reduced CI time.** No Rust compilation in CI pipelines.

### Fallback Behavior

If the precompiled binary for the current platform is not available:

1. Rustler attempts to compile the NIF from source in `native/ex_codecs_native/`.
2. This requires the Rust toolchain (`rustc`, `cargo`) and the Rust dependencies.
3. If compilation fails, the NIF is not loaded and all codecs are registered as unavailable.

This fallback is transparent. The `ExCodecs.Native` module detects whether the NIF loaded successfully, and the application handles the unavailable case gracefully.

## Codec Version Reporting

The NIF provides a `codec_versions/0` function that returns the version of each underlying C/Rust library:

```elixir
ExCodecs.Native.codec_versions()
# => %{
#   "zstd" => "1.5.6",
#   "lz4" => "1.10.0",
#   "snappy" => "1.1.10",
#   "bzip2" => "0.4.4",
#   "blosc2" => "2.14.0"
# }
```

Each codec module uses this to populate its `__codec_info__/0` metadata:

```elixir
defp zstd_version do
  case ExCodecs.Native.codec_versions() do
    %{:zstd => v} -> v
    _ -> "unknown"
  end
rescue
  _ -> "unknown"
end
```

The `rescue` clause handles the case where the NIF is not loaded, ensuring the module does not crash during compilation or when the NIF is unavailable.

## Error Handling in Native Code

When a Rust NIF encounters an error, it is converted to an Elixir error through several layers:

1. **Rust side**: The compression library returns a `Result::Err`. Rustler converts this to an `{:error, reason}` term.
2. **Elixir side**: The codec module does not add additional error handling; the `{:error, reason}` tuple is returned directly.
3. **ExCodecs API**: The `encode/3` and `decode/3` functions wrap the error in an `%ExCodecs.Error{}` struct.

```elixir
# Error wrapping in ExCodecs.Native
def from_nif({:error, reason}, codec) do
  {:error, %ExCodecs.Error{
    reason: nif_error_to_atom(reason),
    message: "NIF error in codec #{codec}: #{inspect(reason)}",
    codec: codec,
    details: reason
  }}
end
```

Common NIF error scenarios:

- **Invalid data**: The decompression input is corrupt or not valid compressed data.
- **Memory allocation failure**: The system is out of memory.
- **Buffer overflow**: The decompressed size exceeds available memory.
- **Internal library error**: The underlying C/Rust library returned an unexpected error.

All of these are caught and returned as `{:error, %ExCodecs.Error{}}` tuples, never as exceptions.

## Summary

- ExCodecs uses Rustler NIFs for all compression operations, providing 10-100x speedup over pure Elixir.
- NIFs run on BEAM Dirty CPU schedulers, preventing them from blocking normal process scheduling.
- Precompiled binaries are distributed for 7 target platforms, requiring no Rust toolchain for installation.
- The registry enables graceful degradation when the NIF is unavailable.
- NIF errors are caught and returned as structured `ExCodecs.Error` tuples, never as exceptions.
- Release-mode compilation with LTO and `codegen-units = 1` ensures maximum performance.