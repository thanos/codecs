# ExCodecs Architecture

An extensible BEAM-native codec framework for Elixir.

## Table of Contents

- [Design Philosophy](#design-philosophy)
- [Architecture Overview](#architecture-overview)
- [Public API](#public-api)
- [Codec Abstraction](#codec-abstraction)
- [Behaviour Design](#behaviour-design)
- [Native Integration](#native-integration)
- [Runtime Codec Discovery](#runtime-codec-discovery)
- [Error Handling](#error-handling)
- [Application Lifecycle](#application-lifecycle)
- [Extensibility Strategy](#extensibility-strategy)
- [Future Categories](#future-categories)

---

## Design Philosophy

ExCodecs is not only a compression library. It is a codec framework with
compression and spatial categories.

The central insight is that many binary transformations -- compression,
hashing, checksums, binary encodings, content addressing -- share the same
essential shape: take binary input, apply a transformation, return binary
output. A codec abstracts this pattern into a uniform interface, regardless of
what kind of transformation is occurring.

Two terminology decisions flow from this insight:

1. **encode/decode** over compress/decompress. The words "compress" and
   "decompress" only make sense for compression. A hash function encodes data
   into a fixed-length digest. A checksum encodes data into a verification
   tag. Base64 encodes binary into ASCII. The encode/decode terminology unifies
   all codec categories under one mental model.

2. **Codec framework, not compression library.** Categories belong to one
   framework but may expose APIs suited to their data shape. Binary→binary
   codecs share the registry behaviour; domain codecs such as spatial formats
   use a category-specific contract. All categories retain the same tagged
   result and structured-error conventions.

The result is an API where `ExCodecs.encode(:zstd, data)` and
`ExCodecs.encode(:sha256, data)` look and feel the same, even though one
reversibly compresses data and the other irreversibly hashes it.

---

## Architecture Overview

```
+------------------------------------------------------------------+
| Public discovery                                                  |
| available_codecs/0,1   supports?/1   codec_info/1                |
+-------------------------------+----------------------------------+
                                |
                       +--------v---------+
                       | Shared catalog   |
                       | CodecRegistry/ETS|
                       +---+----------+---+
                           |          |
              +------------v--+    +--v----------------+
              | :compression  |    | :spatial          |
              | interface:     |    | interface:        |
              | :binary        |    | :spatial          |
              +-------+--------+    +---------+----------+
                      |                       |
      ExCodecs.encode/3, decode/3    ExCodecs.Spatial.encode/2,
                      |               decode/2, stream helpers
       +--------------+------+       +---------+---------+
       | Zstd/LZ4/Snappy/... |       | PLY / EXCP / GSPL |
       +--------------+------+       +-------------------+
                      |
             +--------v---------+
             | Rustler NIFs     |
             | pure-Rust codecs |
             +------------------+
```

Discovery is unified; operation dispatch is category-safe. The catalog's
`interface` metadata prevents top-level binary encode/decode from accidentally
calling a struct↔format codec. `ExCodecs.Spatial` resolves its implementations
from the same catalog.

The implementation is layered in four tiers:

1. **Public API** -- The user-facing `ExCodecs` module providing `encode`,
   `decode`, `available_codecs`, `supports?`, and `codec_info`.

2. **Shared catalog** -- The `CodecRegistry` module backed by an ETS table that
   maps codec atoms to modules, categories, interface shapes, and metadata.

3. **Codec modules** -- Binary modules implement `ExCodecs.Codec`; spatial
   modules expose the category's struct↔format contract.

4. **Native layer** -- Compression modules delegate to the Rustler NIF
   (`ExCodecs.Native`). Spatial codecs keep a pure-Elixir path and, since
   v0.2.3, optional DirtyCpu / mmap acceleration via the same NIF crate.

---

## Public API

The binary registry API is intentionally small (encode/decode plus discovery).
Spatial uses `ExCodecs.Spatial.encode/2` / `decode/2`; top-level
`stream_encode/2` and `stream_decode/2` are convenience delegates for spatial
data. Top-level `encode/3` / `decode/3` are not overloaded for spatial structs.

```elixir
# Encoding and decoding
ExCodecs.encode(:zstd, data, level: 3)       #=> {:ok, binary} | {:error, Error.t()}
ExCodecs.decode(:zstd, compressed)            #=> {:ok, binary} | {:error, Error.t()}

# Discovery
ExCodecs.available_codecs()                    #=> [..., :gsplat, :ply, :spatial_binary, ...]
ExCodecs.available_codecs(:compression)        #=> [:blosc2, :bzip2, :lz4, :snappy, :zstd]
ExCodecs.available_codecs(:spatial)            #=> [:gsplat, :ply, :spatial_binary]
ExCodecs.supports?(:zstd)                     #=> true | false
ExCodecs.codec_info(:zstd)                    #=> {:ok, %Codec{}} | {:error, :unsupported_codec}
```

### Why encode/decode instead of compress/decompress

The encode/decode naming covers all codec categories uniformly:

| Codec Category | "encode" means     | "decode" means     | Reversible? |
|----------------|--------------------|--------------------|-------------|
| Compression    | compress           | decompress         | Yes         |
| Hashing        | compute digest     | (not applicable)   | No          |
| Checksums      | compute checksum   | verify checksum    | Partial     |
| Binary enc.    | encode to format   | decode from format | Yes         |

Compression codecs also provide convenience aliases through the
`ExCodecs.Compression` module:

```elixir
ExCodecs.Compression.compress(:zstd, data)
ExCodecs.Compression.decompress(:zstd, data)
```

These delegate directly to `encode`/`decode` and exist for discoverability and
for developers who prefer domain-specific terminology.

### Unified return type

Every public function returns either `{:ok, result}` or `{:error,
%ExCodecs.Error{}}`. This is a conscious departure from the common Elixir
pattern of returning `{:ok, result} | {:error, reason_atom}`. The structured
error type preserves the reason atom while also carrying the codec name,
a human-readable message, and arbitrary details. This makes error handling
in client code both pattern-matchable and loggable:

```elixir
case ExCodecs.encode(:zstd, data) do
  {:ok, compressed} ->
    # happy path

  {:error, %ExCodecs.Error{reason: :unsupported_codec}} ->
    # handle unknown codec

  {:error, %ExCodecs.Error{reason: :compression_failed, codec: :zstd}} ->
    # handle compression failure
end
```

---

## Codec Abstraction

The `ExCodecs.Codec` behaviour defines the contract that every codec module
must satisfy:

```elixir
defmodule ExCodecs.Codec do
  @callback encode(data :: binary(), opts :: keyword()) ::
              {:ok, binary()} | {:error, ExCodecs.Error.t()}

  @callback decode(data :: binary(), opts :: keyword()) ::
              {:ok, binary()} | {:error, ExCodecs.Error.t()}
end
```

Two callbacks. No optional callbacks. No default implementations. This
minimalism is deliberate. A codec transforms binary input; the encode/decode
pair captures that transformation completely.

### Option validation is the codec's responsibility

The behaviour places option validation on the codec module, not on the
framework. Each codec module validates its own options and returns
`{:error, %ExCodecs.Error{reason: :invalid_options}}` for invalid inputs:

```elixir
# In ExCodecs.Compression.Zstd
def encode(data, opts) when is_binary(data) and is_list(opts) do
  level = Keyword.get(opts, :level, 3)
  with :ok <- validate_level(level) do
    ExCodecs.Native.zstd_compress(data, level)
  end
end

defp validate_level(level) when is_integer(level) and level >= 1 and level <= 22, do: :ok
defp validate_level(_), do: {:error, ExCodecs.Error.new(:invalid_options, ...)}
```

This keeps the behaviour interface stable while allowing each codec to define
its own option schema.

### Codec modules are stateless

No codec module holds state. There are no GenServers, no ETS tables, no
process dictionaries. A codec module is a collection of pure functions that
delegate to the NIF. This makes codec modules trivially testable and safe to
call from any process.

---

## Behaviour Design

### Callbacks

```elixir
@callback encode(data :: binary(), opts :: keyword()) ::
              {:ok, binary()} | {:error, ExCodecs.Error.t()}

@callback decode(data :: binary(), opts :: keyword()) ::
              {:ok, binary()} | {:error, ExCodecs.Error.t()}
```

Both callbacks accept a binary and a keyword list. They return the same type.
This symmetry means the caller never needs to know which callback it is
invoking -- the framework can dispatch based on the codec atom alone.

### Metadata via `__codec_info__/0`

Beyond the behaviour callbacks, each codec module is expected to export a
`__codec_info__/0` function that returns a `%ExCodecs.Codec{}` struct:

```elixir
def __codec_info__ do
  %ExCodecs.Codec{
    name: :zstd,
    category: :compression,
    interface: :binary,
    module: __MODULE__,
    native?: true,
    streaming?: false,
    configurable?: true,
    version: "structured-zstd-0.0.48"
  }
end
```

The `%ExCodecs.Codec{}` struct fields:

| Field           | Type              | Purpose                                         |
|-----------------|-------------------|-------------------------------------------------|
| `name`          | `atom()`          | The codec's registry key                        |
| `category`      | `atom()`          | Category (`:compression`, `:hashing`, etc.)     |
| `interface`     | `:binary \| :spatial` | Operation API shape                         |
| `module`        | `module() \| nil` | The implementing module, or nil if unavailable   |
| `native?`       | `boolean()`        | Whether the codec uses a NIF                    |
| `streaming?`    | `boolean()`        | Whether the codec supports streaming            |
| `configurable?` | `boolean()`        | Whether the codec accepts options               |
| `version`       | `String.t() \| nil` | Library version string                         |

The `__codec_info__/0` convention is deliberately not a behaviour callback.
It is a compile-time function -- the registry calls it during application
startup. Making it a callback would require `Code.ensure_loaded?/1` checks
that add complexity without benefit. Instead, the registry probes for the
function with `function_exported?/3`:

```elixir
defp build_codec_info(name, module, category, interface, metadata) do
  info =
    if function_exported?(module, :__codec_info__, 0) do
      module.__codec_info__()
    else
      %ExCodecs.Codec{}
    end

  %ExCodecs.Codec{
    name: name,
    category: category,
    interface: interface,
    module: module,
    native?: Keyword.get(metadata, :native?, info.native?),
    streaming?: Keyword.get(metadata, :streaming?, info.streaming?),
    configurable?: Keyword.get(metadata, :configurable?, info.configurable?),
    version: Keyword.get(metadata, :version, info.version)
  }
end
```

### Validation with `Codec.validates?/1`

The `ExCodecs.Codec` module provides a validation helper:

```elixir
def validates?(module) do
  Code.ensure_loaded?(module) and
    function_exported?(module, :encode, 2) and
    function_exported?(module, :decode, 2)
end
```

This is used during registration to reject modules that claim to implement
the behaviour but are missing callbacks.

---

## Native Integration

### Rustler and the NIF boundary

All five compression codecs are implemented in Rust and exposed to the BEAM
through Rustler NIFs. The compiled Rust crate produces a `cdylib` that the
BEAM loads at runtime.

```
  Elixir (BEAM)                          Rust (Native)
+------------------+                  +-------------------+
| ExCodecs.Native  | ---- NIF call -->| ex_codecs_native  |
| (Rustler module) |                  | (cdylib crate)    |
+------------------+                  +-------------------+
       |
       | :erlang.nif_error(:nif_not_loaded)  (fallback when NIF absent)
       |
  Graceful degradation
```

The Elixir side is defined in `ExCodecs.Native`:

```elixir
defmodule ExCodecs.Native do
  use RustlerPrecompiled,
    otp_app: :ex_codecs,
    crate: :ex_codecs_native,
    # ... version, base_url, targets ...
end
```

The native crate is pure Rust (structured-zstd, lz4_flex, snap, flate2 rust backend,
libbz2-rs) — no C compression libraries.

Each NIF function has a fallback that returns `:erlang.nif_error(:nif_not_loaded)`:

```elixir
def zstd_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
```

This means that if the NIF is not compiled or fails to load, calls to
`ExCodecs.Native` functions raise an error. The application startup catches
this scenario: if the NIF is not loaded, codecs are registered as unavailable
rather than crashing the application.

### DirtyCpu scheduling

Compression is CPU-intensive work. The BEAM scheduler divides work into
"reductions" and preempts processes that exceed their budget. A single Zstd
compression call on a 10 MB buffer can stall a scheduler thread for hundreds
of milliseconds, causing latency spikes across the entire BEAM.

Rustler's `schedule = "DirtyCpu"` annotation solves this:

```rust
#[rustler::nif(schedule = "DirtyCpu")]
pub fn zstd_compress<'a>(env: Env<'a>, data: Binary, level: i32) -> Term<'a> {
    // ...
}
```

DirtyCpu tells the BEAM to execute the NIF on a dedicated dirty CPU scheduler,
which is not responsible for running normal BEAM processes. Every compression
and decompression NIF in ExCodecs uses `DirtyCpu` scheduling.

The BEAM runs two types of dirty schedulers:

```
+-------------------+     +-----------------------+
| Normal Schedulers |     | Dirty CPU Schedulers  |
| (1 per core)      |     | (configurable count)  |
+-------------------+     +-----------------------+
| Elixir processes  |     | NIF calls that do      |
| OTP tasks         |     | CPU-heavy work         |
| GenServer calls   |     | (compression, hashing) |
+-------------------+     +-----------------------+
```

### The native module structure

The Rust side is organized as one module per codec plus a shared atoms module:

```
native/ex_codecs_native/src/
  lib.rs              -- NIF registration and codec_versions()
  atoms.rs            -- Shared atom definitions (ok, error, etc.)
  zstd_codec.rs       -- Zstd compress/decompress
  lz4_codec.rs        -- LZ4 compress/decompress
  snappy_codec.rs     -- Snappy compress/decompress
  bzip2_codec.rs      -- Bzip2 compress/decompress
  blosc2_codec.rs     -- Blosc2 compress/decompress + shuffle
```

Each codec module follows the same pattern:

1. A `version()` function returning the library version string.
2. A `compress` NIF function annotated with `DirtyCpu`.
3. A `decompress` NIF function annotated with `DirtyCpu`.
4. Consistent error handling returning `{:error, atom}` tuples.

### Precompiled distribution

ExCodecs uses `rustler_precompiled` to ship precompiled NIF binaries, avoiding
the need for users to have a Rust toolchain installed:

```elixir
# mix.exs
defp deps do
  [
    {:rustler, "~> 0.36", optional: true},
    {:rustler_precompiled, "~> 0.8"},
  ]
end
```

Supported targets:

```
aarch64-apple-darwin       (Apple Silicon macOS)
x86_64-apple-darwin        (Intel macOS)
x86_64-unknown-linux-gnu   (x86 Linux, glibc)
x86_64-unknown-linux-musl  (x86 Linux, musl/Alpine)
aarch64-unknown-linux-gnu  (ARM64 Linux, glibc)
aarch64-unknown-linux-musl (ARM64 Linux, musl/Alpine)
x86_64-pc-windows-msvc     (Windows x86_64)
```

The release profile optimizes for size and performance:

```toml
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
strip = true
```

---

## Runtime Codec Discovery

The `ExCodecs.CodecRegistry` is an ETS-backed Agent that serves as the shared
catalog for binary and spatial codec names, implementations, and metadata.

### Why ETS?

ETS offers O(1) lookups for `set`-type tables. Codec resolution happens on
binary and spatial encode/decode calls, so the catalog must be fast. A
GenServer with a map would serialize all lookups through a single process; ETS
allows concurrent reads without bottlenecks.

### Registry data model

Each entry in the ETS table is a tuple:

```elixir
{name :: atom(), {module :: module() | nil, category :: atom(), info :: %ExCodecs.Codec{}}}
```

Example entries:

```elixir
{:zstd,   {ExCodecs.Compression.Zstd,   :compression, %Codec{name: :zstd, ...}}}
{:lz4,    {ExCodecs.Compression.Lz4,    :compression, %Codec{name: :lz4, ...}}}
{:ply,    {ExCodecs.Spatial.Codec.PLY,  :spatial, %Codec{name: :ply, interface: :spatial, ...}}}
{:sha256, {nil, :hashing, %Codec{name: :sha256, module: nil, ...}}}  # unavailable
```

When an implementation cannot load, the module field is `nil` and the codec is
registered as unavailable. Calls through its category API return
`{:error, %ExCodecs.Error{reason: :codec_unavailable}}`.

### Discovery flow

```
  User calls: ExCodecs.encode(:zstd, data)
       |
       v
  CodecRegistry.lookup(:zstd)
       |
       v
  ETS lookup: :ex_codecs_registry
       |
       +---> {:ok, {ExCodecs.Compression.Zstd, :compression, info}}
       |          |
       |          v
       |     info.interface == :binary and module != nil?
       |                              |
       |                             yes --> module.encode(data, opts)
       |
       +---> spatial interface --> return category-API guidance
       |
       +---> {:error, :unsupported_codec}
                  |
                  v
             {:error, %ExCodecs.Error{reason: :unsupported_codec, codec: :zstd}}
```

### API

```elixir
# List all codecs with available implementations
ExCodecs.available_codecs()            #=> [:blosc2, ..., :gsplat, :ply, ..., :zstd]

# Filter available names by category
ExCodecs.available_codecs(:spatial)    #=> [:gsplat, :ply, :spatial_binary]

# List all registered codecs (including unavailable)
ExCodecs.CodecRegistry.all_codecs()    #=> [:blosc2, ..., :ply, :sha256, ..., :zstd]

# Check if a specific codec is available
ExCodecs.supports?(:zstd)              #=> true

# Get detailed metadata
ExCodecs.codec_info(:zstd)
#=> {:ok, %Codec{name: :zstd, category: :compression, interface: :binary, ...}}

ExCodecs.codec_info(:ply)
#=> {:ok, %Codec{name: :ply, category: :spatial, interface: :spatial, ...}}

# Filter by category
ExCodecs.Compression.available_codecs()
#=> [%Codec{name: :zstd, ...}, %Codec{name: :lz4, ...}, ...]
```

---

## Error Handling

### ExCodecs.Error struct

All errors are represented as `%ExCodecs.Error{}` structs that implement the
`Exception` behaviour:

```elixir
defmodule ExCodecs.Error do
  @type error_reason ::
          :unsupported_codec    # The codec atom is not in the registry
        | :codec_unavailable     # The codec exists but its NIF failed to load
        | :invalid_data          # The input is not a binary or is malformed
        | :invalid_options        # The options are out of range
        | :compression_failed     # The NIF returned a compression error
        | :decompression_failed   # The NIF returned a decompression error
        | :nif_not_loaded         # The native library is not available

  defexception [:reason, :message, :codec, :details]
end
```

### Error construction

```elixir
# Direct construction
%ExCodecs.Error{reason: :unsupported_codec, codec: :zstd}

# Via new/2 (fills in default message)
ExCodecs.Error.new(:compression_failed, codec: :zstd)

# Via error/2 (returns {:error, struct} tuple)
ExCodecs.Error.error(:invalid_data, message: "Data must be a binary")
```

### NIF error mapping

The Rust side returns errors as atoms: `{:error, :compression_failed}`,
`{:error, :invalid_data}`, `{:error, :output_limit_exceeded}`, etc. Elixir
codec modules call `ExCodecs.NIF.wrap/2` (or `safe_call/2`) to turn those into
`{:error, %ExCodecs.Error{}}`:

```elixir
# Typical codec decode path
case ExCodecs.NIF.max_output_size(opts) do
  {:ok, max} ->
    ExCodecs.NIF.wrap(:zstd, ExCodecs.Native.zstd_decompress(data, max))

  {:error, _} = err ->
    err
end
```

`NIF.wrap/2` maps known atoms to structured errors with a default message and
`codec:` field. Unknown atoms still become `%ExCodecs.Error{}` with the raw
atom preserved. This keeps a clear boundary: Rust communicates status as
atoms; Elixir enriches them for callers.

### Error flow

```
  Rust NIF                          Elixir
+------------+                +------------------+
| compress() | -- {:error,    | Codec module     |
|             |    :compression|  validates opts  |
|             |    _failed} ---|  calls Native    |--> {:error, %Error{}}
|             |                |  returns result  |
+------------+                +------------------+
```

If the NIF itself raises (unlikely, given Rust's panic safety), Rustler catches
the panic and returns an error atom.

---

## Application Lifecycle

### Startup sequence

```elixir
defmodule ExCodecs.Application do
  use Application

  def start(_type, _args) do
    children = [ExCodecs.CodecRegistry]
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        register_all_codecs()
        {:ok, pid}
      error -> error
    end
  end
end
```

The startup sequence:

1. The `CodecRegistry` Agent starts and creates the ETS table.
2. `register_all_codecs/0` iterates over the known codec list.
3. For each codec, it checks whether the NIF is loaded (`function_exported?`)
   and whether the module implements `encode/2`.
4. If both checks pass, the codec is registered as available.
5. If either check fails, the codec is registered as unavailable (`module: nil`).

```elixir
@codecs [
  {:zstd,   ExCodecs.Compression.Zstd,   :compression},
  {:lz4,    ExCodecs.Compression.Lz4,    :compression},
  {:snappy,  ExCodecs.Compression.Snappy,  :compression},
  {:bzip2,  ExCodecs.Compression.Bzip2,  :compression},
  {:blosc2, ExCodecs.Compression.Blosc2, :compression}
]
```

This design means ExCodecs never crashes at startup due to a missing NIF.
It degrades gracefully: unavailable codecs return
`{:error, %ExCodecs.Error{reason: :codec_unavailable}}` at call time.

---

## Extensibility Strategy

### Adding a new codec to an existing category

To add a new compression codec (e.g., brotli):

1. Create `lib/ex_codecs/compression/brotli.ex` implementing `ExCodecs.Codec`.
2. Add Rust NIF functions in `native/ex_codecs_native/src/brotli_codec.rs`.
3. Register the module in `lib/ex_codecs/application.ex`.
4. Add the NIF functions to `native/ex_codecs_native/src/lib.rs`.
5. Add the crate dependency in `Cargo.toml`.

The public API does not change. `ExCodecs.encode(:brotli, data)` works
automatically once the codec is registered.

### Adding a new codec category

To add a new category (e.g., hashing):

1. Create `lib/ex_codecs/hashing.ex` as the category namespace module,
   mirroring `ExCodecs.Compression`.

2. Create individual codec modules (e.g., `lib/ex_codecs/hashing/sha256.ex`)
   implementing `ExCodecs.Codec`.

3. Add category-specific convenience functions if appropriate
   (e.g., `ExCodecs.Hashing.hash(:sha256, data)` as an alias for `encode`).

4. Register codecs in `application.ex` with the `:hashing` category.

The public API extension is minimal: `ExCodecs.encode(:sha256, data)` works
immediately. The `:category` field in `__codec_info__/0` enables category
filtering via `CodecRegistry.codecs_by_category(:hashing)`.

### Category layout

```
lib/ex_codecs/
  ex_codecs.ex                      # Public API
  codec.ex                          # Behaviour definition
  codec_registry.ex                 # ETS-backed registry
  error.ex                          # Error struct
  native.ex                         # Rustler NIF module
  application.ex                    # Application + registration
  compression.ex                    # Compression namespace
  compression/
    zstd.ex
    lz4.ex
    snappy.ex
    bzip2.ex
    blosc2.ex
  hashing.ex                        # (future) Hashing namespace
  hashing/
    sha256.ex                       # (future)
    blake3.ex                       # (future)
  encoding.ex                       # (future) Binary encoding namespace
  encoding/
    base64.ex                       # (future)
    hex.ex                          # (future)
```

The convention is: one file per codec, one namespace module per category,
and registration in the application callback. This keeps the structure
predictable and navigable.

---

## Codec Categories

### Spatial (since 0.2.0; Rust accel in 0.2.3)

Spatial codecs map structured geometric types to interchange formats. They use
the specialized `ExCodecs.Spatial` API rather than forcing structs through the
binary-only `ExCodecs.Codec` callbacks. They are registered in the shared
catalog with `category: :spatial` and `interface: :spatial`. Hot paths may use
DirtyCpu pack/unpack and mmap-backed file streams when the NIF is loaded
(`accel: false` forces Elixir).

`ExCodecs.available_codecs/0` lists all available entries,
`ExCodecs.available_codecs(:spatial)` filters the shared catalog, and
`ExCodecs.Spatial.available_formats/0` presents spatial formats in the
category's preferred built-in order.

| Format            | Module                              |
|-------------------|-------------------------------------|
| `:ply`            | `ExCodecs.Spatial.Codec.PLY`        |
| `:spatial_binary` | `ExCodecs.Spatial.Codec.Binary`     |
| `:gsplat`         | `ExCodecs.Spatial.Codec.Gsplat`     |

### Future categories (not implemented)

The categories below are **planned but not shipped**. They are sketched here to
illustrate the extensibility model; the code examples are illustrative, not
runnable, and the registry entries shown do not exist today. `:irreversible_codec`
is not in the current `error_reason()` type.

#### Hashing

Hashing codecs encode data into fixed-length digests. Because hashing is
one-way, `decode` will raise or return an error -- it is a symmetric API
over an asymmetric operation.

```elixir
{:ok, digest} = ExCodecs.encode(:sha256, data)
# decode(:sha256, digest) returns {:error, %Error{reason: :irreversible_codec}}
```

The `streaming?` metadata field indicates whether a codec supports incremental
(streaming) hashing. The `configurable?` field indicates whether options like
output length are accepted.

Planned hashing codecs:

| Codec      | Output Length | Notes                           |
|------------|---------------|---------------------------------|
| SHA-256    | 32 bytes      | NIST standard, widely trusted   |
| SHA-3-256  | 32 bytes      | Keccak-based, SHA-3 standard    |
| BLAKE3     | Variable      | Very fast, configurable output  |
| xxHash     | 4/8 bytes     | Non-cryptographic, very fast    |

#### Checksums

Checksum codecs produce small integrity tags. Unlike hashes, checksums may
support a `verify` operation through encode/decode symmetry:

```elixir
{:ok, checksum} = ExCodecs.encode(:crc32, data)
{:ok, verified} = ExCodecs.decode(:crc32, checksum <> data)
```

Or alternatively, a separate verification function.

Planned checksum codecs:

| Codec  | Output Length | Notes                        |
|--------|---------------|------------------------------|
| CRC32  | 4 bytes       | Widely used in networking    |
| Adler32| 4 bytes       | Faster than CRC32, less robust|
| xxHash32| 4 bytes      | Fast non-cryptographic       |

#### Binary Encodings

Binary encoding codecs convert between binary formats and their text
representations:

```elixir
{:ok, text}    = ExCodecs.encode(:base64, binary_data)    # binary -> text
{:ok, binary}  = ExCodecs.decode(:base64, text)           # text -> binary
{:ok, hex_str} = ExCodecs.encode(:hex, binary_data)      # binary -> hex
{:ok, binary}  = ExCodecs.decode(:hex, hex_str)           # hex -> binary
```

Encodings are always reversible, making them ideal candidates for the
encode/decode API.

Planned encoding codecs:

| Codec   | Overhead | Notes                             |
|---------|----------|-----------------------------------|
| Base64  | 33%      | Standard, widely supported        |
| Base32  | 60%      | Case-insensitive, no padding     |
| Base16  | 100%     | Hex encoding                      |
| Base58  | ~37%     | Bitcoin-style, no ambiguous chars|

#### Content Addressing

Content-addressed codecs combine hashing and encoding for use in
content-addressable storage systems:

```elixir
{:ok, cid} = ExCodecs.encode(:cidv1, binary_data, hash: :sha256, codec: :raw)
```

This is the most complex future category because it composes other codecs.
A CIDv1 encode operation internally calls a hash codec and a base encoding
codec, then assembles the result according to the CID specification.

---

The architecture described here accommodates categories through specialized
entry points under one framework. Binary-shaped categories can reuse
`ExCodecs.Codec` and the ETS registry; domain-shaped categories may define
their own behaviour and discovery while preserving common result, error, and
documentation conventions.