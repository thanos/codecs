# Choosing a Compression Codec

This guide helps you select the right compression codec for your use case. It includes a comparison table, decision criteria, and worked examples.

> ### Is the data spatial, or spatially representable?
>
> Compression codecs operate on arbitrary binaries. If records represent
> coordinates, points, normals, colors, oriented particles, or Gaussian splats,
> consider converting them to `ExCodecs.Spatial` types first—even when the
> source is currently a flat array, CSV rows, maps, or database records.
>
> Use:
>
> - `ExCodecs.Spatial.PointCloud` for XYZ, XYZRGB(A), normals, and scalar
>   per-point attributes.
> - `ExCodecs.Spatial.GaussianCloud` for position, scale, rotation, opacity,
>   color, and spherical harmonics.
> - `:ply` for interoperable spatial exchange.
> - `:spatial_binary` (EXCP) for compact point clouds.
> - `:gsplat` (GSPL) for compact Gaussian clouds.
>
> Spatial encoding and compression are complementary. Encode the structured
> data first, then optionally compress the resulting binary:
>
> ```elixir
> alias ExCodecs.Spatial.{Point, PointCloud}
>
> cloud =
>   rows
>   |> Enum.map(fn %{x: x, y: y, z: z} -> Point.new(x, y, z) end)
>   |> PointCloud.new()
>
> {:ok, spatial_binary} =
>   ExCodecs.Spatial.encode(cloud, format: :spatial_binary)
>
> {:ok, compressed} = ExCodecs.encode(:zstd, spatial_binary, level: 3)
> ```
>
> If the numbers have no geometric meaning and only need compact storage,
> Blosc2 may be a better fit. See
> [Understanding Spatial Codecs](understanding_spatial_codecs.md) and
> [Spatial Wire Formats](../docs/spatial_formats.md).

## Quick Comparison

| Codec    | Compression Ratio | Compression Speed | Decompression Speed | Memory Usage | Configurable | Streaming | Best For                          |
|----------|-------------------|-------------------|---------------------|--------------|--------------|-----------|-----------------------------------|
| LZ4      | Low               | Very Fast         | Very Fast           | Very Low     | No           | No        | Real-time, latency-sensitive      |
| Snappy   | Low               | Very Fast         | Very Fast           | Very Low     | No           | No        | Short-lived data, RPC payloads    |
| Zstd     | High              | Fast              | Very Fast           | Moderate     | Levels 1-22  | No        | General purpose, storage, network |
| Bzip2    | Very High         | Slow              | Slow                | Moderate     | Block 1-9    | No        | Archival, offline processing      |
| Blosc2   | High*             | Fast              | Very Fast           | Moderate     | Codec/level/shuffle/typesize | No | Numerical arrays, typed data |

\* Blosc2 ratio depends heavily on the internal codec (`cname`) and shuffle settings. With byte shuffle on typed data, ratios can exceed Zstd.

“Streaming” here means an incremental compression API. All current compression
codecs operate on complete input buffers.

## Decision Framework

Answer the following questions to narrow your choice:

### 1. What is your data type?

- **Coordinates, point samples, particles, normals, or Gaussian splats** --
  model them with `ExCodecs.Spatial`, even if they currently arrive as arrays,
  rows, maps, or CSV. Optionally compress the encoded PLY/EXCP/GSPL binary.
- **Text, JSON, logs, general-purpose binary** -- Zstd is the best default. Use level 3 for a balance of speed and ratio.
- **Typed numerical arrays without spatial semantics (floats, integers, matrices)** -- Blosc2 with appropriate `typesize` and `shuffle` settings.
- **Short-lived messages, RPC payloads** -- Snappy or LZ4 for minimal latency.
- **Archival storage** -- Bzip2 for maximum ratio, or Zstd at level 19-22 for high ratio with better decompression speed.

### 2. How fast does compression need to be?

- **Need >= ~1 GB/s** - LZ4 or Snappy.
- **Need >= ~300-500 MB/s** - Zstd level 1-3, Blosc2 with LZ4 inner codec.
- **No constraint** - Zstd high levels (9-22) or Bzip2.

### 3. How fast does decompression need to be?

- **Need multi-GB/s** - LZ4 or Snappy.
- **Need ~1 GB/s class** - Zstd any level, Blosc2.
- **No constraint** - Any codec. Bzip2 decompression is typically much slower.

### 4. How much memory can you spare?

- **Very constrained (embedded, large concurrent load)** -- LZ4 or Snappy.
- **Moderate** -- Zstd at levels 1-14.
- **Available** -- Zstd at levels 15-22 or Bzip2 at block sizes 7-9.

### 5. Is data read once or many times?

- **Read many times** -- Invest in higher compression. The one-time compression cost amortizes over many decompressions. Zstd level 9-14 or Bzip2.
- **Read once or rarely** -- Use fast compression. LZ4 or Snappy.
- **Never decompressed (checksum only)** -- Consider whether you need compression at all.

## Codec-Specific Selection Guides

### When to Use LZ4

```elixir
{:ok, compressed} = ExCodecs.encode(:lz4, data)
```

- ExCodecs exposes one fixed, fast LZ4 profile; it does not accept `:level`.
- Low-latency message queues
- Real-time data pipelines where throughput matters more than size
- Temporary data that will be decompressed quickly
- In-memory caches where the CPU cost of decompression must be negligible
- When you need deterministic compression and decompression speeds

### When to Use Snappy

```elixir
{:ok, compressed} = ExCodecs.encode(:snappy, data)
```

- RPC frameworks (Snappy is the default in many RPC systems)
- Data that is already partially compressed or has low entropy
- Situations where you want zero configuration
- When every microsecond counts and compression ratio is secondary

### When to Use Zstd

```elixir
{:ok, compressed} = ExCodecs.encode(:zstd, data, level: 3)
```

- General-purpose compression (Zstd is the best default choice)
- Databases, file storage, and network transmission
- Workloads where decompression speed matters (Zstd decompresses fast regardless of compression level)
- When you need a configurable tradeoff (22 levels from fast to maximum ratio)

ExCodecs does not currently expose Zstd dictionary compression.

### When to Use Bzip2

```elixir
{:ok, compressed} = ExCodecs.encode(:bzip2, data, block_size: 9)
```

- Archival storage where maximum ratio is the priority
- Offline batch processing where compression time is not constrained
- Data that will be stored for a long time and decompressed rarely
- Interoperability with the `.bz2` ecosystem

### When to Use Blosc2

```elixir
{:ok, compressed} = ExCodecs.encode(:blosc2, data, cname: :zstd, clevel: 5, shuffle: :byte, typesize: 8)
```

- Numerical arrays (float64, int32, etc.)
- Scientific data, time series, matrix storage
- Situations where shuffle filters provide a significant ratio improvement
- When you need fine-grained control over the compression pipeline

Each Blosc2 NIF call is single-threaded (`nthreads: 1`). Parallelize independent
buffers with BEAM processes.

## Worked Examples

### Example 1: API Response Cache

A web application caches JSON responses. Data is compressed once, read many times.

**Choice: Zstd at level 5-9**

```elixir
# Compression (one-time cost)
{:ok, compressed} = ExCodecs.encode(:zstd, json_binary, level: 7)

# Decompression (many reads)
{:ok, original} = ExCodecs.decode(:zstd, compressed)
```

Rationale: Zstd decompresses quickly regardless of compression level, so invest more in compression to get better ratios for the cache.

### Example 2: Real-Time Message Broker

Messages arrive at high volume and must be forwarded with minimal latency.

**Choice: LZ4**

```elixir
{:ok, compressed} = ExCodecs.encode(:lz4, message)
```

Rationale: Latency is the priority. ExCodecs' fixed fast LZ4 profile adds
minimal overhead to the pipeline.

### Example 3: Scientific Data Archive

A research pipeline archives float64 measurement arrays to cold storage.

**Choice: Blosc2 with Zstd inner codec and byte shuffle**

```elixir
{:ok, compressed} = ExCodecs.encode(:blosc2, float_array_binary,
  cname: :zstd,
  clevel: 9,
  shuffle: :byte,
  typesize: 8
)
```

Rationale: The byte shuffle reorders bytes within each 8-byte float, grouping high-order bytes (often similar) together. On typed arrays this often yields about a 2-4x ratio gain versus compressing the raw array (illustrative; see the Blosc2 guide table).

### Example 4: Log File Archival

Monthly log files are compressed and stored in object storage.

**Choice: Zstd at level 15-19 or Bzip2 at block size 9**

```elixir
{:ok, compressed} = ExCodecs.encode(:zstd, log_data, level: 17)
# or
{:ok, compressed} = ExCodecs.encode(:bzip2, log_data, block_size: 9)
```

Rationale: Compression is a one-time batch operation. Maximum ratio reduces storage costs over months. Zstd at high levels offers better decompression speed than Bzip2 if you need occasional access.

### Example 5: Short-Lived RPC Payload

An internal service sends compressed protobuf messages over the network.

**Choice: Snappy**

```elixir
{:ok, compressed} = ExCodecs.encode(:snappy, protobuf_binary)
```

Rationale: Protobuf already removes much redundancy. Snappy adds minimal overhead on both compression and decompression, and requires no configuration. The ratio improvement will be modest but the latency impact is negligible.

## Summary Table by Use Case

| Use Case                     | Recommended Codec | Configuration                       |
|------------------------------|-------------------|-------------------------------------|
| General-purpose default      | Zstd              | `level: 3`                          |
| Real-time / low-latency      | LZ4               | No codec-specific options            |
| Fastest with no config       | Snappy            | (none)                               |
| Maximum ratio / archival     | Bzip2 or Zstd     | `block_size: 9` or `level: 19-22`   |
| Numerical arrays             | Blosc2            | `cname: :zstd, shuffle: :byte`      |
| Spatially meaningful records | Spatial + optional compression | PLY/EXCP/GSPL, then optionally Zstd |
| Small repetitive payloads    | Zstd              | `level: 3` (dictionary API unavailable) |
| In-memory cache              | LZ4 or Snappy      | No codec-specific options            |
| Already slightly compressed  | Snappy or LZ4      | No codec-specific options            |