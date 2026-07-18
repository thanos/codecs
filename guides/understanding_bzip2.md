# Understanding Bzip2

Bzip2 is a high-ratio compression codec that uses the Burrows-Wheeler Transform. This guide covers how Bzip2 works, its block format, configurable options, and when it is the right choice.

## Overview

Bzip2 was created by Julian Seward in 1996. It provides some of the best compression ratios among general-purpose algorithms, at the cost of significantly slower compression and decompression speeds compared to Zstd, LZ4, and Snappy.

Key characteristics:

- Excellent compression ratio (often better than Zstd at moderate levels).
- Slow compression (50-200 MB/s depending on block size and data).
- Slow decompression (slower than Zstd at any level).
- Higher memory usage during both compression and decompression.
- Configurable block size (1-9) controlling the ratio/speed/memory tradeoff.

## How Bzip2 Works

Bzip2 compression proceeds through four sequential phases:

### Phase 1: Block Sorting (Burrows-Wheeler Transform)

The Burrows-Wheeler Transform (BWT) is the key innovation behind Bzip2. It is a reversible transformation that permutes the input data to group similar characters together.

Given an input string, BWT works as follows:

1. Form all cyclic rotations of the input.
2. Sort the rotations lexicographically.
3. Take the last column of the sorted matrix.
4. Record the original row position for decoding.

Example with input `banana`:

```
Rotations:         Sorted:            Last column:
banana              abanana            b
anana b             anana b            n
nana ba             ana b n            n
ana ban             a banan            a
na bana             banana             a (original row)
a banan             na bana            a
 banan a            nana ba            n
```

The last column output is `bnnaaa` -- notice how similar characters cluster together. This clustering is what makes the subsequent stages effective.

BWT is reversible: given the last column and the original row index, the original string can be reconstructed.

The block size parameter (1-9) controls how large an input block the BWT processes. Larger blocks produce better clustering and better compression, but require more memory and processing time.

### Phase 2: Move-to-Front Transform

After BWT, the data has high local correlation. The Move-to-Front (MTF) transform converts the BWT output into a sequence of small integers:

- Maintain a list of all possible symbols in order.
- For each symbol in the BWT output, find its position in the list and emit that position.
- Move the symbol to the front of the list.

Since similar symbols are clustered after BWT, the MTF output tends to be many small numbers (0s, 1s, 2s) with occasional large numbers. This distribution is ideal for the next phase.

### Phase 3: Run-Length Encoding

Bzip2 applies Run-Length Encoding (RLE) after the MTF transform:

- Sequences of 4 or more identical symbols are replaced by the symbol followed by a run-length count.
- This further reduces the data size, especially for runs that occur naturally after BWT+MTF.

### Phase 4: Huffman Coding

Finally, Huffman coding assigns variable-length codes to each symbol:

- Frequent symbols (small MTF values) get short codes (often 1-2 bits).
- Rare symbols (large MTF values) get longer codes.
- Multiple Huffman tables may be used for different sections of the data, chosen to minimize total bits.

The Huffman tables are stored in the compressed output header so the decompressor can reconstruct them.

## Block Size

Bzip2's block size parameter (1-9) controls the amount of data processed by each BWT pass:

| Block Size | Memory (Compression) | Memory (Decompression) | Ratio    | Speed    |
|------------|----------------------|-------------------------|----------|----------|
| 1          | 1 MB                 | 0.5 MB                  | Lower    | Fastest  |
| 3          | 3 MB                 | 1.5 MB                  | Moderate | Moderate |
| 6          | 6 MB                 | 3 MB                    | Good     | Slower   |
| 9 (default)| 9 MB                | 4.5 MB                  | Best     | Slowest  |

Larger block sizes allow the BWT to find more distant patterns, improving compression. The improvement diminishes for block sizes above 6 for most data.

```elixir
# Default (block size 9, maximum ratio)
{:ok, compressed} = ExCodecs.encode(:bzip2, data)

# Lower block size for faster compression or less memory
{:ok, compressed} = ExCodecs.encode(:bzip2, data, block_size: 3)

# Minimum block size, minimum memory
{:ok, compressed} = ExCodecs.encode(:bzip2, data, block_size: 1)
```

### Choosing a Block Size

- **Block size 9**: Default. Best ratio. Acceptable for offline processing.
- **Block size 6-7**: Good ratio with slightly faster compression. A reasonable compromise.
- **Block size 3-5**: Moderate ratio. Useful when memory is constrained.
- **Block size 1-2**: Fastest Bzip2 compression. Only a small improvement over level 9 Zstd in ratio, but much slower.

ExCodecs does not expose upstream Bzip2's `work_factor` parameter; only
`:block_size` is accepted on encode, and unknown keys are ignored.

## Bzip2 File Format

A Bzip2 compressed stream has the following structure:

```
+----------+--------+----------+--------+----------+
| Stream   | Block  | Block    | Block  | Stream   |
| Header   | 1      | 2        | ...    | Footer   |
| "BZh"    |        |          |        |          |
+----------+--------+----------+--------+----------+
```

**Stream Header**: The magic bytes `BZh` followed by the block size digit (1-9) and the Huffman-used flag.

**Each Block**:
- Magic bytes: `0x314159265359` (pi digits)
- CRC32 of the original data
- BWT pointer (original row index)
- MTF-encoded, Huffman-coded data
- Optional run-length encoding

**Stream Footer**:
- Magic bytes: `0x177245385090` (sqrt(pi) as BCD digits)
- CRC32 of the blocks
- Padding bits

This format allows block-level recovery: if one block is corrupted, subsequent blocks can still be decompressed.

## Performance Characteristics

### Compression Speed

Bzip2 compression is significantly slower than Zstd, LZ4, and Snappy:

| Library      | Compression Speed (approx.) |
|-------------|------------------------------|
| LZ4          | 500+ MB/s                    |
| Snappy       | 500+ MB/s                    |
| Zstd level 3 | 300-500 MB/s                 |
| Zstd level 9 | 50-100 MB/s                  |
| Bzip2 level 9| 10-30 MB/s                   |

### Decompression Speed

Bzip2 decompression is also slower than alternatives:

| Library      | Decompression Speed (approx.) |
|-------------|-------------------------------|
| LZ4          | 2+ GB/s                       |
| Snappy       | 1.5+ GB/s                     |
| Zstd         | 1+ GB/s (any level)           |
| Bzip2        | 50-150 MB/s                   |

### Compression Ratio

Bzip2 achieves excellent ratios, comparable to or slightly better than Zstd at moderate levels:

| Data Type    | Bzip2 Ratio | Zstd L3 Ratio | Zstd L9 Ratio |
|-------------|-------------|----------------|----------------|
| English text | 3.5:1       | 3.0:1          | 3.3:1          |
| JSON         | 4.0:1       | 2.8:1          | 3.2:1          |
| Source code  | 4.5:1       | 3.5:1          | 4.0:1          |

Zstd at higher levels (15-22) typically matches or exceeds Bzip2's ratio with better decompression speed.

## Memory Usage

Bzip2 memory usage depends on the block size:

| Context          | Block Size 1 | Block Size 9 |
|-----------------|---------------|---------------|
| Compression      | ~1 MB         | ~9 MB         |
| Decompression    | ~0.5 MB       | ~4.5 MB       |

These are moderate amounts. On the BEAM, Bzip2 operations run in a DirtyCpu NIF, so this memory is allocated outside the Erlang heap. However, concurrent Bzip2 operations on large blocks can consume significant total memory.

## When to Use Bzip2

### Use Bzip2 When

- **Maximum compression ratio is the priority.** Cold storage, archival, long-term data retention.
- **Compatibility matters.** The `.bz2` format is widely supported across Unix systems.
- **Data is compressed once and decompressed rarely.** The high compression cost is amortized.
- **You need block-level recovery.** Bzip2's stream format allows partial decompression after corruption.

### Consider Alternatives When

- **Real-time or latency-sensitive.** Zstd at level 3-5 provides 80-90% of Bzip2's ratio at 10-30x the speed.
- **Decompression speed matters.** Zstd decompresses 5-20x faster than Bzip2.
- **Memory is constrained.** Bzip2's memory usage, while moderate, exceeds Snappy's or LZ4's minimal footprint.
- **You are compressing small payloads.** Bzip2's block header overhead (100+ bytes) makes it inefficient for data under 1 KB.

## Comparison with Zstd

| Property            | Bzip2          | Zstd                    |
|---------------------|----------------|-------------------------|
| Compression Ratio   | Excellent      | Very Good to Excellent  |
| Compression Speed   | Slow           | Fast to Moderate        |
| Decompression Speed | Slow           | Fast                    |
| Memory (Compress)   | 1-9 MB         | 1-64 MB (level dep.)    |
| Memory (Decompress) | 0.5-4.5 MB     | 1-8 MB                   |
| Streaming            | Yes            | Yes                      |
| Dictionary           | No             | Yes                      |
| Configurable         | Block size     | 22 levels + window size  |

Bzip2's advantage is raw compression ratio on text-heavy data. Zstd's advantage is speed, especially decompression speed. For most new systems, Zstd at level 9-14 provides comparable ratio with dramatically better performance.

## Best Practices

1. **Use Bzip2 for archival, not real-time.** The slow compression and decompression make it unsuitable for interactive workloads.

2. **Use block size 9 by default.** The ratio improvement from larger blocks is worth the memory cost for archival use cases.

3. **Consider Zstd before Bzip2.** Zstd at level 9-14 provides similar ratio with 5-20x better decompression speed. Only choose Bzip2 when you specifically need its format or its marginal ratio improvement.

4. **Do not use Bzip2 for small data.** The block header overhead and BWT setup cost make Bzip2 inefficient for payloads under 1 KB.

5. **Be aware of memory.** Each concurrent Bzip2 compression at block size 9 uses 9 MB. On the BEAM, plan for this when dispatching many concurrent compressions.