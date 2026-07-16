# Understanding Blosc2

ExCodecs implements **C-Blosc2-compatible chunks** only (pure Rust via
`blosc2-pure-rs`). That means:

| You can | You cannot (with ExCodecs alone) |
|---------|----------------------------------|
| `encode(:blosc2, binary)` → one chunk | Open/save `.b2frame` super-chunk files |
| Interop with python-blosc2 `compress`/`decompress` on a buffer | B2ND multi-dim arrays / partial ND slices |
| Use `:blosclz`, `:lz4`, `:lz4hc`, `:zstd`, `:zlib` + shuffle | `cname: :snappy` (use standalone `:snappy` codec) |

**Standalone Snappy** remains `ExCodecs.encode(:snappy, data)`.

Blosc2 is a meta-compressor designed for high-performance compression of binary data, especially numerical arrays. This guide explains how Blosc2 works, its shuffle filters and internal codecs, and how to use it effectively in ExCodecs.

## Overview

Blosc2 is not a compression algorithm itself. It is a **meta-compressor**: a framework that orchestrates other compressors (called "codecs" or "compressors" in Blosc2 terminology) and adds pre-processing and post-processing stages around them.

The key innovation in Blosc2 is combining:

1. **Shuffle filters** that reorganize bytes to improve compressibility of typed data.
2. **Pluggable internal compressors** — in ExCodecs: BloscLZ, LZ4, LZ4HC, Zstd, Zlib
   (not Snappy as `cname`; use the standalone `:snappy` codec for Snappy).
3. **Block-based chunks** — ExCodecs compresses one buffer to one chunk
   (`nthreads: 1` on the NIF; not a multi-chunk super-chunk store).

ExCodecs exposes Blosc2 as a first-class **chunk** codec with configurable
internal compressor, compression level, shuffle mode, and typesize.

## How Blosc2 Works

Blosc2 processes data in a pipeline:

```
Input Binary
    |
    v
[1] Split into internally selected blocks
    |
    v
[2] Apply shuffle filter (none / byte / bit)
    |
    v
[3] Compress each block with internal codec
    |
    v
[4] Assemble one Blosc2 chunk
    |
    v
Output Binary
```

Decompression reverses the pipeline:

```
Input Binary (Blosc2 chunk)
    |
    v
[1] Parse chunk header
    |
    v
[2] Decompress each block with internal codec
    |
    v
[3] Apply inverse shuffle filter
    |
    v
[4] Concatenate blocks
    |
    v
Output Binary (original)
```

### Step 1: Block Splitting

Blosc2 chunks split input into internal blocks. In the wider Blosc2 ecosystem,
blocks can support parallel or partial processing. ExCodecs currently exposes
neither block-size selection nor block-level access; the implementation chooses
the block layout and decodes the complete chunk.

Blocks still improve cache utilization inside compression.

### Step 2: Shuffle Filters

The shuffle filter is Blosc2's most powerful feature for typed data. It reorders bytes within elements before compression:

**Byte Shuffle** (`shuffle: :byte`):

Groups bytes by their position within each element:

```
Original (4x 32-bit integers):
  [A0 A1 A2 A3] [B0 B1 B2 B3] [C0 C1 C2 C3] [D0 D1 D2 D3]

After byte shuffle:
  [A0 B0 C0 D0] [A1 B1 C1 D1] [A2 B2 C2 D2] [A3 B3 C3 D3]
```

High-order bytes (A3, B3, C3, D3) often have similar values (e.g., mostly zeros for positive integers). Grouping them together makes the data far more compressible.

**Bit Shuffle** (`shuffle: :bit`):

The same principle at the bit level, providing even more correlation for certain data types (e.g., floating-point values where the sign bit and exponent are similar across elements).

**No Shuffle** (`shuffle: :none`):

Skip the shuffle step. Use this for data that does not have a regular element structure.

### Step 3: Internal Compression

Each (possibly shuffled) block is compressed using one of several codecs:

| Codec      | Description                                  | Speed         | Ratio     |
|------------|----------------------------------------------|---------------|-----------|
| `:blosclz` | BloscLZ (C-Blosc2 pure-Rust port)            | Very Fast     | Moderate  |
| `:lz4`     | LZ4 (default)                                | Very Fast     | Moderate  |
| `:lz4hc`   | LZ4 high compression                         | Moderate      | Good      |
| `:zstd`    | Zstandard                                     | Fast          | High      |
| `:zlib`    | Zlib (Deflate)                                | Moderate      | Good      |

The choice of internal codec determines the speed/ratio tradeoff within each block. Blosc2 adds the shuffle filtering on top, so the effective ratio can be much higher than using the same codec directly.

### Step 4: Chunk Assembly

Blosc2 assembles the compressed blocks into a chunk with metadata including:

- The decompressed size.
- The block size.
- The internal codec, compression level, and shuffle mode.
- The element typesize.

This header allows decompression without any external metadata.

## Using Blosc2 in ExCodecs

### Basic Usage

```elixir
# Default: LZ4 inner codec, level 5, byte shuffle, typesize 8
{:ok, compressed} = ExCodecs.encode(:blosc2, data)
{:ok, original} = ExCodecs.decode(:blosc2, compressed)
```

### With Zstd Inner Codec

```elixir
{:ok, compressed} = ExCodecs.encode(:blosc2, data,
  cname: :zstd,
  clevel: 5,
  shuffle: :byte,
  typesize: 8
)
```

### With No Shuffle (General Binary Data)

```elixir
{:ok, compressed} = ExCodecs.encode(:blosc2, data,
  cname: :zstd,
  clevel: 3,
  shuffle: :none
)
```

### With Bit Shuffle (Maximum Ratio for Floats)

```elixir
{:ok, compressed} = ExCodecs.encode(:blosc2, data,
  cname: :zstd,
  clevel: 9,
  shuffle: :bit,
  typesize: 4
)
```

### Single-threaded chunk compression

```elixir
{:ok, compressed} = ExCodecs.encode(:blosc2, data,
  cname: :lz4,
  clevel: 5,
  shuffle: :byte,
  typesize: 8
)
```

The current NIF always uses one Blosc2 worker (`nthreads: 1`) on a BEAM
DirtyCpu scheduler. `:numthreads` is not a public option.

## Configuration Options

| Option        | Type             | Default    | Description                                         |
|---------------|------------------|------------|-----------------------------------------------------|
| `:cname`      | atom             | `:lz4`     | Internal compressor (`:blosclz`, `:lz4`, `:lz4hc`, `:zstd`, `:zlib`) |
| `:clevel`    | integer (0-9)    | 5          | Compression level (0 = no compression)             |
| `:shuffle`   | atom             | `:byte`    | Shuffle filter (`:none`, `:byte`, `:bit`)          |
| `:typesize`  | integer (1-255)  | 8          | Element size in bytes for shuffle                   |

### Choosing `cname` (Internal Codec)

- **`:lz4`** (default): Best for speed-sensitive applications. The shuffle filter provides most of the ratio improvement.
- **`:zstd`**: Best ratio when combined with shuffle. Use `:zstd` with `clevel: 5-9` for maximum compression of numerical data.
- **`:lz4hc`**: Higher ratio than `:lz4`, slower compress.
- **`:blosclz`**: Blosc’s own LZ codec (included for C-Blosc2 interop).
- **`:zlib`**: Moderate speed, good ratio. Available for compatibility.

`cname: :snappy` is rejected. Use the standalone registry codec
`ExCodecs.encode(:snappy, data)` instead.

### Choosing `shuffle`

- **`:byte`** (default): Best for most typed data. Groups bytes by position within each element. Recommended for float64, int32, and similar numeric types.
- **`:bit`**: Finest granularity. Groups bits by position. Can improve ratio further for floating-point data where sign/exponent bits are similar.
- **`:none`**: No pre-processing. Use for general binary data without regular element structure, or when the shuffle adds overhead without ratio improvement.

### Choosing `typesize`

The `typesize` tells Blosc2 how many bytes each element occupies. It is critical for the shuffle filter to work correctly.

| Data Type           | typesize |
|---------------------|----------|
| `:float64` / double | 8        |
| `:float32` / float  | 4        |
| `:int64`             | 8        |
| `:int32`             | 4        |
| `:int16`             | 2        |
| `:int8`              | 1        |
| Raw binary (no shuffle)| 1      |

Setting `typesize: 1` with `shuffle: :byte` is equivalent to `shuffle: :none` because there is no intra-element byte grouping.

Setting `typesize: 8` with `shuffle: :byte` on float64 arrays typically provides 2-10x ratio improvement over compressing the raw data directly.

**Important**: The data length should ideally be a multiple of `typesize` for the shuffle filter to work correctly. If the data length is not a multiple of `typesize`, Blosc2 will still work but the last partial element will not benefit from shuffling.

### Choosing `clevel`

| clevel | Behavior                                  |
|--------|-------------------------------------------|
| 0      | No compression (shuffle only)             |
| 1      | Fastest compression                       |
| 5      | Default, good balance                     |
| 9      | Maximum compression for the chosen codec  |

With `clevel: 0`, Blosc2 applies the shuffle filter but does not compress. This is useful when you want the reordering benefit without compression, or as a diagnostic to see how much shuffle alone helps.

### Threading

On the BEAM, the NIF runs on a DirtyCpu scheduler. The pure-Rust
C-Blosc2-compatible chunk implementation uses `nthreads: 1`; ExCodecs does not
create an extra native thread pool. Run independent codec calls concurrently
from separate BEAM processes when workload-level parallelism is needed.

Wire format is a **Blosc2 chunk** (not super-chunk / B2ND / `.b2frame`).
Fixtures under `test/fixtures/blosc2/` are produced with python-blosc2.

## The Blosc2 Chunk Format

ExCodecs produces one C-Blosc2-compatible **chunk** per call. The chunk carries
the decompressed size, compressed size, block size, typesize, codec, level, and
filter metadata required for full-buffer decompression.

The public API only performs complete chunk decompression. It does **not**
expose partial block reads, super-chunks, B2ND arrays, `.b2frame` containers,
or configurable native decompression threads.

## When to Use Blosc2

### Use Blosc2 When

- **Data is numerical arrays.** Float64, int32, and other typed data benefit enormously from shuffle filters.
- **You need fine-grained control.** Blosc2 offers the most parameters of any codec in ExCodecs.
- **Data has regular element structure.** If data length is a multiple of a known typesize, Blosc2 can exploit this.
- **You need C-Blosc2 chunk interoperability.** ExCodecs chunks interoperate
  with single-buffer C/Python Blosc2 compression APIs.

### Consider Alternatives When

- **Data is unstructured binary.** If there is no regular element structure, the shuffle filter provides no benefit, and Zstd or LZ4 directly may be simpler.
- **Data is small.** Blosc2's chunk-header overhead makes it less efficient for data under 256 bytes.
- **You want simplicity.** Blosc2 has many configuration knobs. Zstd with `level: 3` is simpler and effective for most data.

## Ratio Improvement from Shuffle

The shuffle filter is Blosc2's key advantage for numerical data. Here are typical ratio improvements:

| Data Type         | Zstd Alone | Blosc2 + Zstd + Byte Shuffle | Improvement |
|-------------------|------------|-------------------------------|-------------|
| float64 array     | 2.5:1      | 5:1 - 10:1                    | 2-4x        |
| int32 array       | 2.0:1      | 4:1 - 8:1                     | 2-4x        |
| Mixed JSON        | 3.0:1      | 3.0:1 (shuffle: :none)        | No change   |
| Random binary     | 1.01:1     | 1.01:1                        | No change   |

For numerical data, the improvement from shuffle is dramatic and consistent. The more regular the data (arrays of identical types), the greater the benefit.

## Comparison with Other Codecs

| Property           | Blosc2            | Zstd           | LZ4            |
|--------------------|-------------------|----------------|----------------|
| Category            | Meta-compressor  | Algorithm      | Algorithm      |
| Shuffle Filters     | Yes (byte, bit)   | No             | No             |
| Inner Codecs        | 5 options         | N/A            | N/A            |
| Incremental API     | No                | No             | No             |
| Per-call threading  | Single-threaded   | Single-threaded| Single-threaded|
| Best For            | Numerical arrays | General data   | Speed          |
| Configuration       | Codec/level/shuffle/typesize | Level 1-22 | None |

## Best Practices

1. **Set `typesize` correctly.** Match it to your element size (4 for float32, 8 for float64). Wrong typesize reduces or eliminates shuffle benefits.

2. **Use `shuffle: :byte` as the default for typed data.** It provides the most benefit for the least overhead. Switch to `:bit` for floating-point data where exponent bits correlate.

3. **Use `shuffle: :none` for unstructured data.** Shuffle on unstructured data adds CPU overhead without ratio improvement.

4. **Start with `cname: :lz4, clevel: 5` for speed, or `cname: :zstd, clevel: 5` for ratio.** These are the most commonly useful configurations.

5. **Parallelize independent calls with BEAM processes.** Each NIF call is
   single-threaded and runs on a DirtyCpu scheduler.

6. **Benchmark with your actual data.** The effectiveness of shuffle depends heavily on the data. Always measure, do not guess.

7. **Ensure data length is a multiple of typesize.** If possible, pad your data to a typesize boundary before compressing with Blosc2.