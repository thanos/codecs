# Codec Fundamentals

This guide explains the core concepts behind ExCodecs: what codecs are, how the encode/decode abstraction works, and how the framework models them.

## What Is a Codec?

A **codec** (coder-decoder) transforms data between two representations. In the simplest terms:

```
Original Data  --[encode]-->  Transformed Data
Transformed Data  --[decode]-->  Original Data
```

`encode` converts data from its natural form into the codec's target representation. `decode` reverses the process, recovering the original data. For compression codecs, encoding is compression and decoding is decompression.

This abstraction is not limited to compression. Hashing algorithms, checksum functions, binary encodings (Base64, Hex), and content-addressing schemes all follow the same encode/decode pattern. ExCodecs is built on this insight: a unified framework can serve all of these use cases with one consistent API.

## The Encode/Decode Abstraction

Every codec in ExCodecs implements two functions:

```elixir
@callback encode(data :: binary(), opts :: keyword()) :: {:ok, binary()} | {:error, Error.t()}
@callback decode(data :: binary(), opts :: keyword()) :: {:ok, binary()} | {:error, Error.t()}
```

Key properties of this design:

- **Binary in, binary out** for **registry** codecs. Structured data is either
  serialized first, or handled by a **category module** (e.g. spatial structs
  via `ExCodecs.Spatial`).
- **Optionally configurable.** The `opts` keyword list allows codec-specific tuning (compression level, block size, shuffle mode) while keeping the call signature uniform.
- **Explicit error handling.** Every operation returns `{:ok, result}` or `{:error, %ExCodecs.Error{}}`. There are no exceptions for normal failure modes.
- **Composable.** Because the input and output share the same type, codecs can be chained: encode with Zstd, then encode the result with Blosc2 if desired.
- **Category modules** provide domain naming (`Compression.compress/3`) or
  non-binary shapes (`Spatial.encode/2`) without overloading the registry API.

### Compressing Data

```elixir
{:ok, compressed} = ExCodecs.encode(:zstd, my_binary)
```

### Decompressing Data

```elixir
{:ok, original} = ExCodecs.decode(:zstd, compressed)
```

### With Codec-Specific Options

```elixir
{:ok, compressed} = ExCodecs.encode(:zstd, my_binary, level: 9)
{:ok, compressed} = ExCodecs.encode(:blosc2, my_binary, cname: :zstd, clevel: 5, shuffle: :byte)
```

## How ExCodecs Models Codecs

The framework is organized around three layers: the public API, the registry, and codec modules.

```
+-------------------+
| ExCodecs (API)    |   Public interface: encode/3, decode/3
+-------------------+
         |
+-------------------+
| CodecRegistry     |   Runtime discovery: lookup, supports?, available_codecs
+-------------------+
         |
+-------------------+
| Codec Behaviour   |   Contract: encode/2, decode/2, __codec_info__/0
+-------------------+
         |
+-------------------+
| Codec Modules     |   Implementations: Zstd, Lz4, Snappy, Bzip2, Blosc2
+-------------------+
         |
+-------------------+
| Native NIFs       |   Rust implementations via Rustler
+-------------------+
```

### The Codec Behaviour

`ExCodecs.Codec` defines the contract every codec must fulfill:

```elixir
defmodule ExCodecs.Codec do
  @callback encode(data :: binary(), opts :: keyword()) :: {:ok, binary()} | {:error, Error.t()}
  @callback decode(data :: binary(), opts :: keyword()) :: {:ok, binary()} | {:error, Error.t()}
end
```

Codec modules also export `__codec_info__/0` to provide metadata:

```elixir
def __codec_info__ do
  %ExCodecs.Codec{
    name: :zstd,
    category: :compression,
    module: __MODULE__,
    native?: true,
    streaming?: true,
    configurable?: true,
    version: "1.5.6"
  }
end
```

The `%ExCodecs.Codec{}` struct contains:

| Field             | Type              | Description                                        |
|-------------------|-------------------|----------------------------------------------------|
| `name`            | `atom()`          | Codec identifier (e.g., `:zstd`)                  |
| `category`        | `atom()`          | Category (e.g., `:compression`)                   |
| `module`          | `module() \| nil` | Implementing module, or `nil` if unavailable      |
| `native?`         | `boolean()`       | Whether a native NIF implementation exists         |
| `streaming?`      | `boolean()`       | Whether the codec supports streaming operation     |
| `configurable?`   | `boolean()`       | Whether the codec accepts configuration options    |
| `version`         | `String.t() \| nil` | Library version string                          |

### The Codec Registry

`ExCodecs.CodecRegistry` is an ETS-backed registry that maps codec names to their implementations. It is populated during application startup in `ExCodecs.Application`:

```elixir
# At startup, each codec is checked for availability
codecs = [
  {:zstd, ExCodecs.Compression.Zstd, :compression},
  {:lz4, ExCodecs.Compression.Lz4, :compression},
  {:snappy, ExCodecs.Compression.Snappy, :compression},
  {:bzip2, ExCodecs.Compression.Bzip2, :compression},
  {:blosc2, ExCodecs.Compression.Blosc2, :compression}
]

for {name, module, category} <- codecs do
  if nif_loaded?() and Code.ensure_loaded?(module) and function_exported?(module, :encode, 2) do
    CodecRegistry.register(name, module, category)
  else
    CodecRegistry.register_unavailable(name, category)
  end
end
```

If a native NIF library fails to load, the codec is still registered but marked unavailable. This is **graceful degradation**: your application can query `ExCodecs.supports?(:zstd)` before attempting to use a codec.

### The Error Model

All errors are structured through `ExCodecs.Error`:

```elixir
%ExCodecs.Error{
  reason: :unsupported_codec | :codec_unavailable | :invalid_data |
          :invalid_options | :compression_failed | :decompression_failed |
          :nif_not_loaded,
  message: String.t(),
  codec: atom() | nil,
  details: term() | nil
}
```

Common error scenarios:

```elixir
# Unknown codec
ExCodecs.encode(:unknown, "data")
# => {:error, %ExCodecs.Error{reason: :unsupported_codec, codec: :unknown}}

# Codec known but NIF not loaded
ExCodecs.decode(:zstd, corrupt_data)
# => {:error, %ExCodecs.Error{reason: :decompression_failed, codec: :zstd}}

# Invalid option
ExCodecs.encode(:zstd, "data", level: 50)
# => {:error, %ExCodecs.Error{reason: :invalid_options, message: "Level must be an integer between 1 and 22"}}
```

Pattern matching on errors:

```elixir
case ExCodecs.encode(:zstd, data) do
  {:ok, compressed} ->
    handle_success(compressed)

  {:error, %ExCodecs.Error{reason: :codec_unavailable}} ->
    fallback_to_pure_elixir()

  {:error, %ExCodecs.Error{reason: :invalid_options} = error} ->
    Logger.error("Bad options: #{error.message}")
    {:error, :bad_options}
end
```

You can also use the convenience matcher:

```elixir
if ExCodecs.Error.matches?(result, :unsupported_codec) do
  handle_missing_codec()
end
```

## Implementing a Custom Codec

To add a new codec, implement the `ExCodecs.Codec` behaviour and register it:

```elixir
defmodule ExCodecs.Compression.MyCodec do
  @behaviour ExCodecs.Codec

  def __codec_info__ do
    %ExCodecs.Codec{
      name: :my_codec,
      category: :compression,
      module: __MODULE__,
      native?: false,
      streaming?: false,
      configurable?: false,
      version: "1.0.0"
    }
  end

  @impl true
  def encode(data, opts) do
    # Your compression logic here
    {:ok, compressed_data}
  end

  @impl true
  def decode(data, opts) do
    # Your decompression logic here
    {:ok, original_data}
  end
end
```

Then register it at application startup:

```elixir
ExCodecs.CodecRegistry.register(:my_codec, ExCodecs.Compression.MyCodec, :compression)
```

## Summary

- A codec transforms data through `encode` and `decode`, both accepting binaries and optional keyword lists.
- The `ExCodecs.Codec` behaviour defines the contract; the registry manages runtime discovery.
- All errors are structured as `%ExCodecs.Error{}` with typed reasons.
- Codecs that cannot load their native implementation are still registered but marked unavailable, enabling graceful degradation.
- New codecs can be added by implementing the behaviour and registering them with the ETS-backed registry.