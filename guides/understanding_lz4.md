# Understanding LZ4

LZ4 is the fastest codec in ExCodecs, designed for applications where speed is paramount. This guide covers how LZ4 works, its performance characteristics, the block format, and how to use it effectively.

## Overview

LZ4 was created by Yann Collet (the same author as Zstd) and is focused on extreme speed. It provides:

- Compression speeds over 500 MB/s per core.
- Decompression speeds over 2 GB/s per core.
- A simple, well-defined block format.
- A fixed fast-compression profile in ExCodecs.

LZ4 achieves this speed by using a simple hash table for match finding and avoiding computationally expensive entropy coding. The tradeoff is a lower compression ratio compared to Zstd or Bzip2.

## How LZ4 Works

LZ4 is an LZ77-family algorithm. It operates in a single pass over the input:

### Match Finding

1. The input is read byte by byte.
2. At each position, LZ4 computes a hash of the next 4 bytes and looks up the hash table.
3. If the hash table contains a matching position, LZ4 verifies the match by comparing bytes.
4. If the match is at least 4 bytes long, it emits a `(offset, match_length)` pair and copies the match.
5. If no match is found, the current byte is emitted as a literal.
6. The hash table is updated with the current position.

### What LZ4 Skips

Unlike Zstd or Deflate, LZ4 does **not** perform:

- No entropy coding (Huffman or FSE). Matches and literals are stored with minimal overhead.
- No optimal parsing. The first match found is used; no search for a better match.
- No context modeling. Each match decision is local.

This simplicity is what makes LZ4 fast. The compressed data is essentially a stream of "copy these literal bytes, then copy `length` bytes from `offset` back."

## Configuration

The ExCodecs LZ4 codec uses `lz4_flex` fast block compression and does **not**
expose compression levels or LZ4 HC. Pass no codec-specific encode options:

```elixir
{:ok, compressed} = ExCodecs.encode(:lz4, data)
```

If you need a configurable speed/ratio tradeoff, use Zstd. If you need an
LZ4-family codec with a higher-compression profile, Blosc2 supports
`cname: :lz4hc` and `clevel: 0..9`.

## The LZ4 Block Format

Each LZ4 compressed block consists of sequences. Each sequence encodes:

```
+----------+---------+-----------+
| Token    | Literals| Match     |
| (1 byte) | Section | Section   |
+----------+---------+-----------+
```

### Token Byte

The token byte encodes two values (4 bits each):

- **Literal length** (high 4 bits): Number of literal bytes before the match.
- **Match length** (low 4 bits): Length of the match minus 4 (minimum match length is 4).

If either value is 15, the remaining length is encoded as successive bytes where value 255 means "add 255 and read the next byte."

### Literals Section

Raw bytes that did not match anything in the sliding window.

### Match Section

- **Offset** (2 bytes, little-endian): Distance back to the start of the match.
- **Extended match length** (if the token's match length was 15): Additional bytes encoding the remaining match length.

This format is simple to parse, which contributes to LZ4's fast decompression speed.

## Performance Characteristics

### Compression Speed

LZ4's fixed fast profile can compress at 500+ MB/s on modern hardware. This means:

- A 1 MB payload compresses in under 2 ms.
- A 10 MB payload compresses in under 20 ms.
- Network links below 500 MB/s are often slower than LZ4 compression, making on-the-fly compression a net win.

### Decompression Speed

LZ4 decompresses at 2+ GB/s. This is often faster than memory copy for partially incompressible data because the compressed representation is smaller and fewer bytes need to be read from memory.

### Compression Ratio

On typical text data, LZ4 achieves:

- 2.0:1 to 2.5:1 on English text.
- 1.5:1 to 2.0:1 on JSON.
- 1.0:1 on already-compressed data (JPEG, PNG, encrypted).

These ratios are lower than Zstd (3:1 to 5:1 on the same data) but the speed advantage can make LZ4 more effective when latency is the bottleneck.

## Sliding Window

LZ4 uses a 64 KB sliding window for match finding. This is fixed and not configurable. The window size means:

- Matches can reference data up to 64 KB back.
- Patterns repeated at distances greater than 64 KB cannot be compressed.
- For data with long-range repetitions, Zstd (with its larger window) achieves significantly better ratios.

## When LZ4 Excels

- **Network protocol compression.** When data must be compressed and decompressed within strict latency budgets.
- **In-memory caches.** Compressing cached data reduces memory usage while keeping decompression instant.
- **Log buffering.** Compressing log lines before writing to disk reduces I/O without adding noticeable latency.
- **Real-time data pipelines.** Streaming systems where backpressure from compression is unacceptable.
- **IPC/RPC serialization.** Compressing messages between services with minimal overhead.

## When LZ4 Is Not the Best Choice

- **Cold storage.** Use Zstd or Bzip2 for better ratios when decompression speed is less important.
- **Small, structured messages.** Consider Snappy for even simpler compression with no configuration.
- **Numerical arrays.** Use Blosc2 with shuffle filters for better ratios on typed data.
- **Data with long-range patterns.** LZ4's 64 KB window misses patterns beyond 64 KB. Zstd's larger window captures them.

## Comparison with Snappy

LZ4 and Snappy occupy a similar niche (fast, low-ratio compression). Key differences:

| Property          | LZ4                           | Snappy                        |
|-------------------|-------------------------------|-------------------------------|
| Compression Speed | ~500 MB/s (fixed fast profile)| ~500 MB/s                    |
| Decompression Speed | ~2 GB/s                     | ~1.5 GB/s                    |
| Compression Ratio | Moderate (better than Snappy)| Slightly lower               |
| Configurable      | No                            | No                            |
| Format            | LZ4 block format             | Snappy framework format       |
| Deterministic     | Yes                          | Yes                           |

LZ4 generally offers better ratio at comparable speeds, while Snappy has a simpler format and no configuration knobs.

## Comparison with Zstd

| Property          | LZ4              | Zstd                  |
|-------------------|------------------|-----------------------|
| Compression Speed | Faster           | Slower (at high levels)|
| Decompression Speed| Faster          | Fast                  |
| Ratio             | Moderate         | High                  |
| Window Size       | 64 KB (fixed)   | Up to 8 MB+ (configurable) |
| Dictionary       | No               | Not exposed by ExCodecs |
| Configurable      | No               | Levels 1-22            |

LZ4 is the right choice when speed is the primary concern. Zstd is the right choice when ratio matters or when you need fine-grained control over the speed/ratio tradeoff.

## Best Practices

1. **Use LZ4 without level options.** ExCodecs exposes its fixed fast profile.
   If ratio matters, consider Zstd or Blosc2 with `cname: :lz4hc`.

2. **Measure the compression ratio on your data.** If LZ4 provides less than 1.5:1 ratio, compression may not be worth the CPU cost.

3. **Use LZ4 for data that is compressed and decompressed frequently.** The multi-GB/s decompression speed means the decompression cost is often negligible.

4. **Do not re-compress LZ4 data.** Already-compressed data (including LZ4 output) typically does not compress further and may expand.

5. **Consider the 64 KB window.** If your data has repetitive patterns at distances greater than 64 KB, LZ4 will not capture them. Switch to Zstd for a larger window.