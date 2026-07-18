# Compression Fundamentals

This guide covers the fundamentals of lossless data compression: how algorithms work, what tradeoffs exist, and how to reason about compression in practice.

## Why Compression Matters

Data compression reduces the number of bits needed to represent information. The benefits cascade:

- **Less storage.** Compressed data takes up fewer bytes on disk.
- **Less network bandwidth.** Transferring compressed payloads reduces latency and cost.
- **Better cache utilization.** More compressed data fits in CPU caches and memory.
- **Faster I/O.** Disk and network are often the bottleneck; reducing data size can reduce total wall-clock time even after accounting for CPU overhead.

Compression is not free. It consumes CPU time and memory. The central question is always: **does the reduction in I/O cost justify the CPU cost?**

## Lossless vs. Lossy Compression

ExCodecs deals exclusively with **lossless** compression: the decoded output is bit-for-bit identical to the original input.

| Property     | Lossless                          | Lossy                            |
|-------------|-----------------------------------|----------------------------------|
| Fidelity     | Exact reconstruction              | Approximate reconstruction       |
| Ratio        | Lower (typically 2:1 to 5:1)     | Higher (10:1 to 100:1+)         |
| Use cases    | Text, code, databases, archives   | Images, audio, video             |
| Examples     | Zstd, LZ4, Bzip2, Snappy         | JPEG, MP3, H.264                 |

Never use a lossy codec on data that must be reconstructed exactly (database records, source code, configuration files, structured data).

## How Compression Algorithms Work

All lossless compression algorithms exploit statistical redundancy in the input. They find patterns and represent them more compactly. Different algorithms use different techniques, often in combination.

### Run-Length Encoding (RLE)

The simplest approach: replace repeated sequences with a count.

```
Input:  AAAAAABBCCDDDD
Output: 6A2B2C4D
```

RLE is effective for data with long runs of identical values but poor for varied data. It is rarely used standalone but appears as a building block inside more sophisticated algorithms.

### Dictionary Methods (LZ77/LZ78/LZW)

The most influential family. These algorithms build a dictionary of previously seen substrings and replace repeated occurrences with references.

**LZ77** (used by LZ4, Snappy, Zstd, Deflate/GZIP):

- Maintain a sliding window over recently seen data.
- When a substring matches something in the window, emit a `(distance, length)` pair pointing back to it.
- Literals that have not been seen before are emitted as-is.

```
Input:  "the quick brown fox the quick"
Output: "the quick brown fox" <distance=26, length=9>
```

The sliding window size determines the maximum reference distance. Larger windows improve ratio but use more memory.

**LZ78/LZW** (used by Unix `compress`, GIF):

- Build an explicit dictionary that grows during compression.
- When a new string is found, add it to the dictionary for future reference.
- Dictionary indices are emitted as codes.

### Entropy Coding (Huffman, Arithmetic)

After dictionary or transform-based processing, entropy coding assigns shorter bit sequences to more frequent symbols.

**Huffman coding** builds an optimal prefix-free code tree:

- Count the frequency of each symbol.
- Build a binary tree where frequent symbols get short codes and rare symbols get long codes.
- No code is a prefix of another, so decoding is unambiguous.

**Arithmetic coding** achieves higher efficiency by representing the entire message as a single fractional number, approaching the theoretical Shannon entropy limit.

### Burrows-Wheeler Transform (BWT)

Used by Bzip2. Not a compression algorithm by itself, but a reversible transformation that makes data more compressible:

1. Form all cyclic rotations of the input.
2. Sort them lexicographically.
3. Take the last column of the sorted matrix.

The last column tends to group identical characters together, making it highly amenable to run-length and entropy encoding. BWT achieves excellent compression ratios because it captures long-range redundancy.

### Shuffle Filters

Used by Blosc2. Before compression, the bytes within typed elements are grouped by position:

```
Original (4x 32-bit integers):
  [A0 A1 A2 A3] [B0 B1 B2 B3] [C0 C1 C2 C3] [D0 D1 D2 D3]

After byte shuffle:
  [A0 B0 C0 D0] [A1 B1 C1 D1] [A2 B2 C2 D2] [A3 B3 C3 D3]
```

High-order bytes (which are often zero or similar in numeric data) cluster together, dramatically improving compression ratios. Bit shuffle performs the same operation at the bit level for even higher correlation.

## The Compression Tradeoff Space

No single algorithm is best on all axes. Compression involves tradeoffs among:

### Compression Ratio vs. Speed

Higher compression ratios require more computation. Zstd level 1 is fast with moderate ratio; Zstd level 22 is slow with excellent ratio.

```
Ratio     Low <---------------------------------------> High
Speed      High <---------------------------------------> Low
           Snappy  LZ4  Zstd(1)  Zstd(3)  Zstd(9)  Bzip2(9)
```

### Compression Speed vs. Decompression Speed

Some algorithms are asymmetric. Zstd optimizes for fast decompression regardless of compression level. LZ4 has extremely fast both directions. Bzip2 is slow in both directions.

### Memory Usage

Higher compression levels and larger window sizes consume more memory:

| Codec   | Compression Memory | Decompression Memory |
|---------|-------------------|----------------------|
| LZ4     | Low               | Very Low             |
| Snappy  | Very Low          | Very Low             |
| Zstd    | Moderate-High     | Low                  |
| Bzip2   | Moderate          | Moderate             |
| Blosc2  | Configurable      | Low-Moderate         |

### Determinism

All ExCodecs backends produce deterministic output for a given input, fixed
options, and library version: the same `encode(:zstd, data, level: 3)` call
yields byte-identical output across calls. Output is **not** guaranteed across
library versions — a new structured-zstd release may produce a different (but
compatible) frame for the same input.

## When Compression Helps and Hurts

Compression helps when:

- Data has redundant patterns (text, JSON, CSV, log files).
- I/O (disk or network) is the bottleneck.
- You are storing or transmitting data that will be read many times.
- The data is large relative to the compression overhead.

Compression hurts when:

- Data is already compressed (JPEG, PNG, video codecs, encrypted data). Re-compressing usually inflates size.
- Data is very small (under a few hundred bytes). The compressed output may be larger than the input.
- CPU is the bottleneck and I/O is fast (e.g., in-memory processing of short-lived data).
- Latency is critical and the compression overhead exceeds I/O savings.

## Practical Guidelines

1. **Measure, do not guess.** Benchmark your actual data with multiple codecs. Text data compresses differently from binary data, and JSON compresses differently from protobuf.

2. **Choose decompression speed over compression speed** for read-heavy workloads. Data is typically compressed once and decompressed many times.

3. **Reserve high-compression settings for archival.** Zstd level 19-22 and Bzip2 are appropriate for cold storage, not for real-time processing.

4. **Watch your memory.** High compression levels consume more RAM. On the BEAM, NIFs run in dirty schedulers, but memory pressure still affects the entire system.

5. **Test with realistic data.** Synthetic benchmarks are misleading. Use production data or representative samples.

6. **Consider Blosc2 for typed arrays.** If your data is numerical (float arrays, integer matrices), Blosc2's shuffle filters can improve ratios by about 2-4x compared to applying a general-purpose codec directly (illustrative; measure on your data).