# Understanding Zstd

Zstandard (Zstd) is the default codec for most use cases in ExCodecs. This guide provides a deep dive into how Zstd works, its compression levels, dictionary compression, and how to get the most out of it.

## Overview

Zstd was created by Yann Collet at Facebook and released in 2016. It is a modern lossless compression algorithm that combines:

- A high-speed LZ77-style dictionary matching phase.
- A finite-state entropy coding phase (FSE, a variant of arithmetic coding).
- Configurable compression levels from 1 (fastest) to 22 (smallest).

Zstd is designed to decompress at high speed regardless of the compression level used. This makes it ideal for write-once, read-many workloads.

## How Zstd Works

Zstd compression proceeds in three phases:

### Phase 1: Dictionary Matching (LZ77)

Zstd scans the input using a sliding window. It searches backward for the longest match to the current position and emits a `(offset, match_length)` pair. Shorter matches that are unlikely to improve compression are skipped to save time.

The sliding window size determines how far back the algorithm can reference.
ExCodecs does not currently expose a `window_log` option; the pure-Rust backend
uses its default window behaviour.

### Phase 2: Sequence Encoding

The matches and literals from phase 1 are encoded as three sequences:

- **Literals**: bytes that did not match anything in the window.
- **Offsets**: the distance back to the matching string.
- **Match lengths**: the length of each match.

Each of these three streams is encoded separately.

### Phase 3: Entropy Coding (FSE)

Zstd uses Finite State Entropy (FSE) encoding, which is a fast variant of arithmetic coding. FSE approaches the theoretical minimum number of bits per symbol while being significantly faster than Huffman coding for non-power-of-2 probability distributions.

This is where Zstd gains its efficiency advantage over older algorithms like Deflate (which uses Huffman only).

## Compression Levels

Zstd levels range from 1 to 22. The tradeoff is compression ratio vs. CPU time:

| Level | Relative Speed | Relative Ratio | Decompression Speed |
|-------|---------------|-----------------|---------------------|
| 1     | Very Fast     | Moderate        | Fast (unchanged)    |
| 3     | Fast (default)| Good            | Fast (unchanged)    |
| 5-7   | Moderate      | Very Good       | Fast (unchanged)    |
| 9-14  | Slow          | Excellent       | Fast (unchanged)    |
| 15-19 | Very Slow     | Near-Optimal   | Fast (unchanged)    |
| 20-22 | Extremely Slow| Optimal        | Fast (unchanged)    |

Key insight: **decompression speed is independent of compression level.** A file compressed at level 22 decompresses just as fast as one compressed at level 1. This is one of Zstd's most important properties.

### Choosing a Level

```elixir
# Default (level 3) - good balance
{:ok, compressed} = ExCodecs.encode(:zstd, data)

# Fast compression, moderate ratio
{:ok, compressed} = ExCodecs.encode(:zstd, data, level: 1)

# High ratio, slower compression (e.g., for archival)
{:ok, compressed} = ExCodecs.encode(:zstd, data, level: 12)

# Maximum ratio (very slow, use for off-line processing only)
{:ok, compressed} = ExCodecs.encode(:zstd, data, level: 22)
```

General recommendations:

- **Levels 1-3**: Real-time systems, data pipelines, network compression.
- **Levels 4-9**: General-purpose storage, databases, caches.
- **Levels 10-14**: Archival, batch processing, cold storage.
- **Levels 15-22**: Extreme ratio scenarios. Only use if compression time is irrelevant.

## Dictionary Compression

Zstd supports **dictionary compression** for improving ratios on small data. Normally, compression algorithms need a large enough input to build an effective dictionary. With a pre-trained dictionary, even small inputs (a few hundred bytes) can achieve significant compression.

### How It Works

1. **Train** a dictionary on a representative sample of your data.
2. **Compress** each small payload using the trained dictionary.
3. **Decompress** using the same dictionary.

The dictionary is typically 8-112 KB and is stored alongside or referenced by the compressed data. It captures the common patterns of your data domain, so small payloads benefit from the dictionary's knowledge.

### When to Use Dictionaries

- Small messages (under 100 KB) that share common structure.
- JSON or protocol buffers with repeated schemas.
- Log entries or metrics that follow a pattern.
- When you control both the compression and decompression side.

ExCodecs currently provides block-level compression and decompression. Dictionary support requires managing the dictionary bytes externally and passing them through a custom Codec module that wraps `ExCodecs.Native` calls with dictionary parameters.

## Streaming

Zstd supports streaming (incremental) compression and decompression. This is useful when data is too large to fit in memory or when you need to process data as it arrives.

ExCodecs currently exposes **block-level** operations only (`streaming?: false`).
Streaming support for arbitrarily large inputs may be added in future versions.

## Zstd Frame Format

A Zstd compressed frame has the structure:

```
+--------+----------+---------+----------+
| Magic  | Frame    | Blocks  | Checksum |
| Number | Header   |         | (opt)    |
| 4B     | variable | variable| 0-8B     |
+--------+----------+---------+----------+
```

- **Magic Number**: `0xFD2FB528` (4 bytes) identifies the data as Zstd.
- **Frame Header**: Contains the decompressed size (if known), window size, dictionary ID, and content checksum flag.
- **Blocks**: One or more compressed blocks, each with a 3-byte header.
- **Checksum**: Optional 4-byte XXH64 checksum of the original data.

Properties of this format:

- The decompressed size can be known in advance (if the compressor provided it) or discovered only during decompression.
- Multi-block frames allow streaming compression.
- Skippable frames allow embedding arbitrary metadata between Zstd frames.

## Window Log

Window size is not configurable in ExCodecs today (no `window_log` option).

- Default: automatically determined based on the level and input size.
- Minimum: 10 (1 KB window).
- Maximum: 30 (1 GB window) for 64-bit systems.

A larger window improves compression on files with distant repetition but increases memory usage during both compression and decompression.

## Memory Usage

Zstd memory usage depends on the compression level and window size:

| Direction   | Memory Usage                                      |
|-------------|---------------------------------------------------|
| Compress L1 | ~8 MB (hash table + window)                       |
| Compress L3 | ~8 MB                                             |
| Compress L9 | ~32 MB                                            |
| Compress L22| high (backend-dependent)                         |
| Decompress  | ~window size (typically 8 MB, up to 128 MB+)     |

On the BEAM, compression runs in a DirtyCpu NIF, so this memory is allocated outside the Erlang heap. That memory pressure still affects the system, so be aware of these numbers when running many concurrent compressions.

## Comparison with Other Algorithms

| Property          | Zstd       | GZIP (Deflate) | LZ4      | Bzip2       |
|-------------------|------------|----------------|----------|-------------|
| Ratio (typical)   | Very Good  | Good           | Moderate | Excellent   |
| Compress Speed    | Fast       | Moderate       | Very Fast| Slow        |
| Decompress Speed  | Very Fast  | Fast           | Very Fast| Slow        |
| Dictionary Support| Yes        | No             | No       | No          |
| Streaming          | Yes        | Yes             | No       | Yes         |
| Configurable       | 22 levels  | 9 levels        | 16 levels| 9 blocks    |

Zstd is strictly superior to GZIP/Deflate on both ratio and speed. It is the recommended default for new systems.

## Best Practices

1. **Start with level 3.** It is the default for good reason: strong ratio with fast compression and decompression.

2. **Measure on your data.** Synthetic benchmarks do not reflect real-world performance. Compress 100 MB of your actual data at each level and observe the ratio and timing.

3. **Use higher levels for write-once, read-many workloads.** The one-time compression cost is amortized over many fast decompressions.

4. **Reserve levels 15-22 for batch processing.** These levels can be 5-20x slower than level 3 for modest ratio improvements (typically 2-5% additional compression).

5. **Watch memory at high levels.** Large payloads require room for input and output buffers (block API).

6. **Consider dictionary compression for small payloads.** If you are compressing many small messages with shared structure, a trained dictionary can double or triple compression ratios.