# Understanding Snappy

Snappy (formerly Zippy) is a fast compression codec developed by Google, focused on maximum speed with minimal configuration. This guide covers Snappy's format, performance characteristics, and when to use it.

## Overview

Snappy was designed at Google for internal use in their distributed infrastructure (Bigtable, MapReduce, etc.). Its priorities, in order, are:

1. **Decompression speed** -- as fast as possible.
2. **Compression speed** -- nearly as fast as decompression.
3. **Simplicity** -- no configuration knobs, deterministic output.
4. **Compression ratio** -- secondary to speed.

Snappy achieves compression speeds over 500 MB/s and decompression speeds over 1.5 GB/s, making it suitable for latency-sensitive systems where the compression ratio is not the primary concern.

## How Snappy Works

Snappy is an LZ77-family algorithm with aggressive speed optimizations:

### Matching Strategy

1. Scan the input linearly.
2. At each position, hash the next 4 bytes and look up a hash table.
3. If a match is found that is at least 4 bytes long (up to 64 KB back), emit a copy command.
4. If no match is found, emit the current byte as a literal.
5. Moves forward by only 1 byte after a literal (no lazy or optimal parsing).

### Speed Optimizations

Snappy makes specific design choices that sacrifice ratio for speed:

- **No entropy coding.** Literals and match lengths are stored in a simple variable-length encoding, not Huffman or arithmetic coding.
- **No optimal parsing.** The first match found is always used. Snappy does not consider whether skipping a match could lead to a longer one later.
- **No match length extension.** Snappy does not extend matches beyond the initial find. Some implementations do, but the core format does not require it.
- **Minimal branching.** The decoder is a simple state machine with few conditional branches, which is CPU-cache and branch-predictor friendly.

## Snappy Format

ExCodecs uses the **raw Snappy block** format (not the separate Snappy framing format). A block is an uncompressed-length prefix followed by tagged elements.

### Uncompressed Length Prefix

```
+-------------------+
| Length (varint)   |  -- Uncompressed length in bytes
+-------------------+
```

The uncompressed size is encoded as a variable-length integer at the start of the compressed block so the decompressor can size the output buffer.

### Elements

Each element starts with a tag byte. The lower two bits select the element type:

| Tag (bits 1-0) | Type |
|----------------|------|
| `00` | Literal (raw bytes) |
| `01` | Copy with 1-byte offset (length 4-11, offset 0-2047) |
| `10` | Copy with 2-byte offset (length 1-64, offset 0-65535) |
| `11` | Copy with 4-byte offset (legacy; length 1-64) |

```
Tag byte:
  bits 7-2: length or offset info (depends on type)
  bits 1-0: element type
```

For literals, short lengths fit in the tag; longer literals use a 1-4 byte length field. Copies encode offset and length as described in Google's Snappy format description. Typical compressor windows are up to 64 KB.

### Format Properties

- **Self-contained.** Each Snappy-compressed block contains all the information needed for decompression. No external dictionary or state is required.
- **Deterministic.** Identical inputs always produce identical outputs. This is useful for content-addressable storage and caching.
- **Single-pass.** Both compression and decompression are single-pass with no backtracking.

## Performance Characteristics

Speeds and ratios below are illustrative order-of-magnitude figures from
typical upstream C Snappy discussions; ExCodecs uses the pure-Rust `snap`
crate. Benchmark your own data.

### Compression Speed

Snappy is designed for very high compression throughput. Key factors:

- The hash table is small and fits in L1/L2 cache.
- No expensive operations (no sorting, no entropy coding, no optimal parsing).
- Good SIMD acceleration on x86 and ARM.

### Decompression Speed

Decompression is similarly speed-oriented. The decompressor:

- Reads the tag byte to determine the element type.
- For literals: copies bytes verbatim (essentially a memcpy).
- For copies: reads the offset and length, then copies from the already-decompressed output.

### Compression Ratio

Snappy's ratio is lower than LZ4, Zstd, and Bzip2. Illustrative ratios:

| Data Type    | Snappy Ratio | LZ4 Ratio | Zstd Level 3 Ratio |
|-------------|--------------|-----------|---------------------|
| English text | 1.8:1       | 2.0:1     | 3.0:1               |
| JSON         | 1.7:1       | 1.9:1     | 2.8:1               |
| HTML         | 2.0:1       | 2.2:1     | 3.5:1               |
| Already compressed | 1.0:1  | 1.0:1     | 1.0:1               |

Snappy's lower ratio is the expected tradeoff for its speed advantage.

## Using Snappy in ExCodecs

Snappy has no encode-time configuration knobs (`configurable?: false`):

```elixir
# Compress
{:ok, compressed} = ExCodecs.encode(:snappy, data)

# Decompress
{:ok, original} = ExCodecs.decode(:snappy, compressed)
```

Encode ignores option keywords. Decode accepts `:max_output_size` (same
decompression-bomb guard as other codecs):

```elixir
{:ok, compressed} = ExCodecs.encode(:snappy, data)
{:ok, original} = ExCodecs.decode(:snappy, compressed, max_output_size: 1_048_576)
```

```elixir
{:ok, info} = ExCodecs.codec_info(:snappy)
info.configurable?  # => false
info.streaming?      # => false
```

## Streaming Support

Snappy supports a framing format (the "Snappy framing format" or "snappy-framed") in its full specification, which allows incremental compression and decompression of data streams.

ExCodecs currently provides block-level Snappy compression and decompression. The entire input must be available before compression can begin. For streaming use cases, consider chunking the data into blocks and compressing each block separately.

## When to Use Snappy

### Use Snappy When

- **Latency is the primary concern.** Snappy adds the least overhead to your data pipeline.
- **Data is short-lived.** Messages in RPC frameworks, temporary caches, inter-process communication.
- **You want simplicity.** No configuration, deterministic output, no versioning concerns.
- **Data has low entropy.** When the compression ratio matters less than the speed.
- **Interoperability with Google systems.** Snappy is native to Bigtable, MapReduce, Protobuf, and other Google infrastructure.

### Consider Alternatives When

- **Storage efficiency matters.** Zstd at level 3 achieves 30-50% better ratio with modest compression time penalty and still-fast decompression.
- **You need maximum speed with better ratio.** LZ4 offers better ratio at comparable speed.
- **Data is numerical arrays.** Blosc2 with shuffle filters far outperforms Snappy on typed data.
- **You need streaming.** Snappy's block format requires the entire input. Use Zstd for streaming.

## Comparison with LZ4

Snappy and LZ4 serve a similar niche. The main differences:

| Property           | Snappy              | LZ4                         |
|--------------------|---------------------|-----------------------------|
| Compression Speed  | Fast                | Fast (fixed fast profile)   |
| Decompression Speed| Fast                | Very fast                   |
| Ratio              | Slightly lower      | Slightly higher             |
| Configuration      | None                | None (no levels in ExCodecs) |
| Format complexity  | Simple              | Slightly more complex       |
| Deterministic      | Yes                 | Yes                         |
| Max offset         | 64 KB               | 64 KB                       |

In practice, LZ4 usually compresses slightly better and decompresses slightly faster. Snappy's advantage is its simpler format and zero configuration.

## Best Practices

1. **Use Snappy for RPC and messaging.** The combination of speed and determinism makes it ideal for network protocols.

2. **Do not use Snappy for archival.** The compression ratio is too low for storage use cases. Use Zstd instead.

3. **Pre-allocate decompression buffers.** Snappy encodes the decompressed size in the frame header, allowing you to allocate the exact output buffer.

4. **Arrays with shuffle:** use Blosc2 with `cname: :lz4` (or `:zstd`), not
   `cname: :snappy` — Snappy is not a standard C-Blosc2 inner codec in ExCodecs.
   For pure Snappy, use this codec: `ExCodecs.encode(:snappy, data)`.

5. **Measure on your data.** If Snappy provides less than 1.3:1 ratio, compression may not be worthwhile. Consider passing data through uncompressed.