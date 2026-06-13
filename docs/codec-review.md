# ExCodecs Codec Review

A detailed technical review of each compression codec available in ExCodecs,
covering history, design goals, performance characteristics, ecosystem
adoption, licensing, Rust ecosystem maturity, and tradeoffs.

## Table of Contents

- [Zstandard (Zstd)](#zstandard-zstd)
- [LZ4](#lz4)
- [Snappy](#snappy)
- [Bzip2](#bzip2)
- [Blosc2](#blosc2)
- [Comparison Table](#comparison-table)
- [Decision Guide](#decision-guide)

---

## Zstandard (Zstd)

### History

Zstandard was created by Yann Collet at Facebook (now Meta) and first released
in 2016. Collet is also the creator of LZ4. Zstd was developed to provide a
compression algorithm that offered both high ratios and high speeds, filling
the gap between LZ4 (fast but lower ratio) and zlib/bzip2 (high ratio but
slow). Facebook deployed Zstd at scale across their infrastructure, and it has
since become one of the most widely adopted modern compression algorithms.

### Design Goals

Zstd was designed around four principles:

1. **High ratio at reasonable speed**: Zstd should compress better than zlib
   at comparable or faster speeds, and decompress significantly faster than
   zlib across all levels.

2. **Configurable tradeoff**: The 22 compression levels allow users to choose
   any point on the speed/ratio curve, from near-LZ4 speeds to near-bzip2
   ratios.

3. **Fast decompression**: Regardless of compression level, decompression
   speed remains consistently high. This is because decompression is a
   simpler, more predictable operation that benefits from optimized rouiting.

4. **Dictionary compression**: Zstd supports training dictionaries for
   compressing many small, structurally similar payloads (e.g., JSON API
   responses) where traditional compression performs poorly.

### Compression Ratio

Zstd achieves strong compression ratios across its level range:

| Level | Ratio (Silesia corpus) | Compression Speed | Decompression Speed |
|-------|------------------------|--------------------|---------------------|
| 1     | ~2.8x                  | ~520 MB/s          | ~1300 MB/s          |
| 3     | ~3.0x (default)       | ~430 MB/s          | ~1300 MB/s          |
| 9     | ~3.4x                  | ~140 MB/s          | ~1300 MB/s          |
| 19    | ~3.7x                  | ~14 MB/s           | ~1300 MB/s          |
| 22    | ~3.8x                  | ~4 MB/s            | ~1300 MB/s          |

The decompression speed is nearly constant regardless of compression level.
At level 22, the compressed output is smaller but decompresses just as fast
as level 1 output.

### Speed Characteristics

- **Compression**: Highly variable by level. Level 1 approaches LZ4 speeds.
  Level 19+ enters the territory of slow but thorough compression suitable
  for archival.
- **Decompression**: Extremely fast and consistent. Typical decompression
  speeds exceed 1 GB/s, making Zstd an excellent choice for read-heavy
  workloads.
- **Memory**: Zstd uses a sliding window for compression (controlled by
  `window_log`). Larger windows improve ratio but require more memory.

### Ecosystem Adoption

Zstd has seen massive adoption since its release:

- **Linux kernel**: Zstd is used for kernel and initramfs compression since
  Linux 4.14 (2017).
- **File systems**: Btrfs, SquashFS, and F2FS support Zstd compression.
- **Web**: Chrome supports Zstd content encoding (Accept-Encoding:
  zstd). CloudFlare and Facebook serve Zstd-compressed responses.
- **Archiving**: tar, rsync, and various backup tools support Zstd.
- **Data formats**: Zstd is a registered compression format in Apache
  Parquet, Zarr, and several database systems.
- **GitHub**: Uses Zstd for Git object compression.
- **Docker**: Container image layers can be compressed with Zstd.

### Licensing

Zstd is dual-licensed under:

- **BSD 3-Clause** (patent grant included) -- for general use
- **GPLv2** -- for GPL-compatible projects

The dual licensing ensures broad compatibility. The BSD license is the
default and covers the vast majority of use cases. Meta has also committed
not to assert patents against Zstd users.

### Rust Ecosystem Maturity

The `zstd` crate (used by ExCodecs) is well-maintained and wraps the
reference C implementation via the `zstd-sys` crate.

| Aspect        | Status                                           |
|---------------|--------------------------------------------------|
| Crate         | `zstd` v0.13                                    |
| Backend       | C FFI to libzstd (reference implementation)      |
| Streaming     | Supported (encode/decode all, bulk, streaming)    |
| Dictionary    | Supported via `zstd::dict`                       |
| Maintenance   | Actively maintained, follows zstd releases       |
| Safety        | FFI boundary is unsafe; crate provides safe API  |

The use of the C reference implementation via FFI is standard practice in the
Rust ecosystem. Pure Rust Zstd implementations exist but are not mature enough
for production use. The `zstd` crate abstracts the FFI boundary with a safe
API, and Rustler further wraps it in a safe NIF interface.

### Tradeoffs

| Pro                                            | Con                                            |
|------------------------------------------------|------------------------------------------------|
| Excellent ratio/speed tradeoff                 | C dependency via zstd-sys (build complexity)   |
| Fast decompression at all levels               | Higher memory usage at high levels             |
| Wide ecosystem adoption and tooling             | NIF binary size larger than pure-Rust codecs   |
| 22 compression levels for fine control         | Dictionary training requires separate tooling  |
| Strong IP position (BSD + patent grant)        | Not the fastest compress (LZ4 is faster)       |
| Active development and optimization             |                                                |

---

## LZ4

### History

LZ4 was created by Yann Collet in 2011 as an evolution of his earlier
LZ4Ultra and FastLZ algorithms. Collet designed LZ4 to prioritize compression
and decompression speed above all else. Its design is rooted in the LZ77
family of algorithms, with aggressive optimizations for modern CPU
architectures. LZ4 rapidly gained adoption in real-time systems, log
processing, and anywhere that throughput matters more than ratio.

### Design Goals

1. **Speed above all**: LZ4 targets compression at over 1 GB/s and
   decompression at multi-GB/s speeds. It achieves this through a minimal
   match format and branch-free decompression loops.

2. **Simple format**: The LZ4 block format is deliberately minimal -- a
   sequence of token bytes, literal lengths, match lengths, and offsets.
   This makes implementations easy to verify and fast to parse.

3. **Low memory footprint**: LZ4 uses a small hash table for compression
   (typically 16 KB) and requires no additional memory for decompression.

4. **Deterministic performance**: LZ4's speed is consistent and predictable,
   with minimal variance across input types. There are no pathological inputs
   that cause dramatic slowdowns.

### Compression Ratio

LZ4 prioritizes speed over ratio. Typical ratios on the Silesia corpus:

| Variant   | Ratio  | Compression Speed | Decompression Speed |
|-----------|--------|--------------------|---------------------|
| LZ4       | ~2.1x  | ~700 MB/s          | ~3000 MB/s           |
| LZ4 HC    | ~2.5x  | ~40 MB/s           | ~3000 MB/s           |

These ratios are lower than Zstd or Bzip2, but the speed advantage is
enormous -- LZ4 decompresses 3-4x faster than Zstd and 10-30x faster than
Bzip2.

### Speed Characteristics

- **Compression**: LZ4 block compression is among the fastest general-purpose
  algorithms available. LZ4 HC trades compression speed for better ratio
  but remains fast to decompress.
- **Decompression**: LZ4 decompression is exceptionally fast (3+ GB/s on
  modern hardware) because the format is designed for branch-free, SIMD-
  friendly decompression loops.
- **Memory**: Minimal. Compression uses a configurable hash table (default
  16 KB). Decompression requires only the input and output buffers.

### Ecosystem Adoption

- **Linux kernel**: LZ4 has been used for kernel and zram compression since
  Linux 3.15 (2014).
- **File systems**: Btrfs, SquashFS, and F2FS support LZ4.
- **Databases**: Redis uses LZ4 for list compression. MongoDB supports LZ4
  for document compression.
- **Messaging**: Apache Kafka supports LZ4 compression for topic data.
- **Networking**: OpenVPN and various VPN products use LZ4 for in-flight
  compression.
- **Logging**: Various log aggregation tools use LZ4 for real-time
  compression of log streams.

### Licensing

LZ4 is licensed under **BSD 2-Clause** (simplified BSD license). This is a
permissive license with no patent concerns.

### Rust Ecosystem Maturity

ExCodecs uses `lz4_flex`, a pure Rust LZ4 implementation:

| Aspect        | Status                                           |
|---------------|--------------------------------------------------|
| Crate         | `lz4_flex` v0.11                                |
| Backend       | Pure Rust (no C FFI)                             |
| Format        | LZ4 block and frame format                       |
| Safety        | 100% safe Rust                                  |
| Maintenance   | Actively maintained                              |

The choice of `lz4_flex` over the C-based `lz4` crate was deliberate:

1. **No C dependency**: Pure Rust avoids build complexity and cross-
   compilation issues. This is especially important for `rustler_precompiled`
   targets.
2. **Safety**: No unsafe FFI boundary. The entire compression and
   decompression path is safe Rust.
3. **Simplicity**: The pure Rust crate has fewer build dependencies and
   produces smaller binaries.
4. **Performance**: `lz4_flex` achieves comparable speeds to the C reference
   implementation on modern hardware.

### Tradeoffs

| Pro                                            | Con                                            |
|------------------------------------------------|------------------------------------------------|
| Extremely fast compression and decompression   | Lower compression ratio                        |
| Pure Rust implementation (lz4_flex)            | Not suitable for archival or storage            |
| Minimal memory usage                           | Large inputs can produce marginal ratios        |
| Deterministic, predictable speed               | LZ4 HC (higher ratio) is much slower           |
| Simple, well-understood format                 | No streaming support in ExCodecs yet           |
| No C dependencies for cross-compilation        | Frame format not exposed in current API         |

---

## Snappy

### History

Snappy was originally created by Google under the name "Zippy" and was
renamed and open-sourced as Snappy in 2011. It was designed for internal use
in Google's infrastructure -- compressing data for Bigtable, MapReduce, and
inter-process communication. Snappy's design philosophy centers on maximum
throughput with minimal CPU overhead, targeting the use case where data is
compressed for transient transport and decompressed immediately on the other
end.

### Design Goals

1. **Maximum throughput**: Snappy targets compression speeds exceeding
   500 MB/s and decompression speeds exceeding 1.5 GB/s. It sacrifices
   compression ratio to achieve this.

2. **Minimal overhead**: The Snappy format adds very little metadata.
   The overhead for incompressible data is minimal (typically 5-6 bytes
   per 32 KB block plus the literals).

3. **Stability**: Snappy's format and behavior are deterministic. The same
   input always produces the same output. This makes it suitable for
   content-addressable storage where bit-exact reproduction is required.

4. **Simplicity**: Snappy has no configuration options. There is one
   compression strategy, one decompression path, and one output format.
   This makes it easy to implement correctly and fast to verify.

### Compression Ratio

Snappy achieves the lowest compression ratios among the ExCodecs codecs,
which is the expected tradeoff for its speed:

| Metric                     | Typical Value (Silesia) |
|----------------------------|-------------------------|
| Compression ratio          | ~2.0x                   |
| Compression speed          | ~500-600 MB/s            |
| Decompression speed        | ~1500-2000 MB/s          |

For structured data (JSON, protocol buffers), Snappy typically achieves
2.0-2.5x compression. For random binary data, it may produce output larger
than the input (though the format handles this gracefully).

### Speed Characteristics

- **Compression**: Extremely fast and consistent. Snappy uses a simple hash
  table and short match encoding. There are no expensive computations.
- **Decompression**: Among the fastest decompressors available. The format
  is designed for SIMD-friendly, branch-predictable decompression.
- **Memory**: Very small. Compression uses a ~32 KB hash table.
  Decompression is single-pass with no additional allocation beyond the
  output buffer.

### Ecosystem Adoption

- **Google infrastructure**: Bigtable, MapReduce, Protocol Buffers (as an
  option), and many internal Google systems.
- **Apache projects**: Hadoop, Cassandra, and various Apache databases
  support Snappy compression.
- **Data formats**: The Snappy framing format is used in Parquet, ORC, and
  other columnar storage formats.
- **Networking**: Various RPC frameworks support Snappy for compressing
  request/response payloads.

### Licensing

Snappy is licensed under **BSD 3-Clause**. Google holds the copyright and
has made no patent claims related to Snappy.

### Rust Ecosystem Maturity

ExCodecs uses the `snap` crate:

| Aspect        | Status                                           |
|---------------|--------------------------------------------------|
| Crate         | `snap` v1.1                                      |
| Backend       | Pure Rust                                        |
| Format        | Raw and framing format supported                  |
| Safety        | Mostly safe Rust; some unsafe for SIMD paths     |
| Maintenance   | Actively maintained                              |

The `snap` crate implements both the raw (block) format and the framing
format. ExCodecs uses only the raw format (`snap::raw::Encoder` and
`snap::raw::Decoder`), which is the simpler and faster of the two.

### Tradeoffs

| Pro                                            | Con                                            |
|------------------------------------------------|------------------------------------------------|
| Extremely fast compression and decompression   | Lowest compression ratio in the set            |
| No configuration needed (one mode)             | No tunable parameters at all                   |
| Simple, well-tested format                     | Not suitable for archival or storage           |
| Deterministic output (same input = same output)| May expand random/incompressible data           |
| Pure Rust implementation available              | Less flexible than LZ4 (no HC variant)        |
| Very small memory footprint                    | Deprecated at Google in favor of Zstd          |

**Note on Snappy's future**: Google has largely moved to Zstd for internal use.
Snappy remains widely deployed and supported, but it is effectively in
maintenance mode. New projects should consider Zstd or LZ4 instead, unless
they need Snappy for compatibility with existing data formats.

---

## Bzip2

### History

Bzip2 was created by Julian Seward in 1996 and released as open source. It
was one of the first widely available compression algorithms to use the
Burrows-Wheeler Transform (BWT), a technique discovered by Michael Burrows
and David Wheeler in 1994. Seward's insight was that BWT followed by
move-to-front coding and Huffman coding could achieve compression ratios
competitive with PPM (Prediction by Partial Matching) algorithms at much
higher speeds. Bzip2 quickly became a standard for software distribution and
archival on Unix systems.

### Design Goals

1. **High compression ratio**: Bzip2 targets compression ratios competitive
   with the best available algorithms. It consistently achieves among the
   highest ratios of any lossless general-purpose compressor.

2. **Recoverability**: Bzip2's block-based structure allows partial
   decompression. If a compressed file is damaged, the blocks before the
   damage can still be recovered.

3. **Simplicity of interface**: Bzip2 has a simple API with one primary
   parameter -- block size (1-9). This makes it easy to integrate and
   difficult to misconfigure.

4. **Stability**: The bzip2 format has been stable since 2000. Compressed
   data from 2000 can still be decompressed today.

### Compression Ratio

Bzip2 achieves the highest compression ratios among ExCodecs' general-purpose
codecs:

| Block Size | Ratio (Silesia) | Compression Speed | Decompression Speed |
|------------|------------------|--------------------|---------------------|
| 1          | ~2.9x            | ~15 MB/s           | ~30 MB/s            |
| 5          | ~3.2x            | ~10 MB/s           | ~28 MB/s            |
| 9 (default)| ~3.3x           | ~8 MB/s            | ~25 MB/s            |

These ratios are higher than Zstd at level 9-19 but come at a significant
speed cost. Bzip2 is roughly 50-100x slower at decompression than LZ4.

### Speed Characteristics

- **Compression**: Slow. Bzip2's BWT and Huffman coding passes are
  computationally expensive. At block size 9, compression speeds are under
   10 MB/s.
- **Decompression**: Also slow compared to modern algorithms. The BWT
  inverse transform requires significant computation per block.
- **Memory**: Increases with block size. At block size 9, compression
   requires approximately 8 MB of memory for the BWT workspace. This is
   significantly more than LZ4 (16 KB) or Zstd (varies by level).
- **Blocking**: Bzip2 processes data in 100 KB - 900 KB blocks (controlled
   by block size). This provides natural boundaries for parallel processing
   (though ExCodecs does not currently expose parallel decompression).

### Ecosystem Adoption

- **Software distribution**: Many Linux distributions distribute source
  tarballs as `.tar.bz2`. The kernel was historically distributed as
  `.tar.bz2` before moving to Zstd.
- **Archival**: Bzip2 is widely used for long-term storage where ratio
  matters more than speed.
- **Unix standard**: `bzip2` has been a standard Unix tool for decades.
  Every major Linux distribution includes it.
- **Data exchange**: Some scientific data formats use bzip2 for compressing
  large datasets.

### Licensing

Bzip2 uses a **BSD-like license** (based on the BSD 4-Clause license with an
additional advertising clause). The license is permissive and similar in
spirit to BSD, though the advertising clause is somewhat unusual.

### Rust Ecosystem Maturity

ExCodecs uses the `bzip2` crate:

| Aspect        | Status                                           |
|---------------|--------------------------------------------------|
| Crate         | `bzip2` v0.4                                    |
| Backend       | C FFI to libbz2 (reference implementation)       |
| Streaming     | Supported (BzEncoder, BzDecoder)                 |
| Safety        | Unsafe FFI boundary; safe Rust API wrapper        |
| Maintenance   | Maintained, follows libbz2 releases              |

The `bzip2` crate wraps the reference C implementation (`libbz2`) via FFI.
There is no mature pure Rust bzip2 implementation; the BWT and Huffman coding
are complex enough that a from-scratch Rust implementation would require
significant engineering and verification effort.

ExCodecs uses the streaming API (`bzip2::write::BzEncoder` and
`bzip2::read::BzDecoder`) even for one-shot compression/decompression.
This is because the streaming API handles the block-based nature of bzip2
correctly and allows the same code path to be extended for streaming support
in the future.

### Tradeoffs

| Pro                                            | Con                                            |
|------------------------------------------------|------------------------------------------------|
| Highest compression ratio (general purpose)     | Very slow compression and decompression        |
| Stable format (unchanged since 2000)            | High memory usage at large block sizes         |
| Block-based (partial recovery on corruption)    | C dependency via bzip2-sys                     |
| Simple API (one parameter: block size)         | No streaming support in ExCodecs yet          |
| Widely available utility (bzip2 command)        | Not suitable for real-time applications        |
| Strong data integrity checks                    | Single-threaded (no parallel compression)    |

---

## Blosc2

### History

Blosc2 was created by Francesc Alted starting in 2021, building on the
original Blosc (created in 2010). Blosc was designed as a meta-compressor
for numerical data in scientific computing, particularly for the PyTables
and bcolz projects. The "Blosc" name comes from "Blocking and Shuffling
Optimized Compression." Blosc2 extended the original format with a new
header structure, support for more internal compressors, and improved
multithreading.

Blosc2's key insight is that numerical arrays (float64, int32, etc.) compress
much better when the bytes are rearranged before compression. By transposing
an array so that similar-valued bytes are adjacent, standard compressors
like LZ4 and Zstd achieve dramatically better ratios on structured data.

### Design Goals

1. **Meta-compression**: Blosc2 is not a compression algorithm itself. It is
   a framework that applies byte/bit shuffling followed by an internal
   compressor (LZ4, Zstd, Snappy, BloscLZ, or zlib). The caller chooses
   both the compressor and the shuffle strategy.

2. **Array-optimized**: Blosc2 is designed for data whose length is a
   multiple of `typesize` -- the size of each element in the array. When
   `typesize` is set correctly and shuffle is enabled, compression ratios
   on numerical arrays can improve by 2-10x.

3. **Zero-overhead passthrough**: When compression produces output larger
   than the input (common with small or random data), Blosc2 stores the
   data uncompressed with minimal overhead -- just the 16-byte header.

4. **Multithreading**: The C-Blosc2 library supports multi-threaded
   compression and decompression via a thread pool. (Note: ExCodecs'
   pure Rust implementation currently uses single-threaded mode.)

5. **Self-describing format**: The Blosc2 header includes the compressor
   type, compression level, shuffle mode, and typesize, allowing
   decompression without external metadata.

### Compression Ratio

Blosc2's ratio depends heavily on the data type and shuffle setting:

| Data Type              | Shuffle   | Internal | Ratio (typical) |
|------------------------|-----------|----------|-----------------|
| Float64 array          | byte      | LZ4      | 4-10x            |
| Float64 array          | byte      | Zstd     | 6-15x            |
| Float64 array          | none      | LZ4      | 1.5-3x           |
| Float64 array          | none      | Zstd     | 2-5x             |
| Random binary          | none      | any      | ~1.0x (passthrough) |
| JSON text              | none      | Zstd     | 2-3x             |

The shuffle step is what makes Blosc2 exceptional for typed arrays. Consider
an array of 64-bit floats: `[1.0, 2.0, 3.0, ...]`. In memory, this looks like:

```
Byte layout (8 bytes per float, no shuffle):
[3f f0 00 00 00 00 00 00] [40 00 00 00 00 00 00 00] [40 08 00 00 00 00 00 00]
  ^-- float 1.0 -----------  ^-- float 2.0 -----------  ^-- float 3.0 ----------

Byte layout (after byte shuffle, grouping bytes by position):
[3f 40 40 ...] [f0 00 08 ...] [00 00 00 ...] [00 00 00 ...] [00 00 00 ...] [00 00 00 ...] [00 00 00 ...] [00 00 00 ...]
  ^-- byte 0      ^-- byte 1     ^-- byte 2     ... (repeated zeros = excellent compression)
```

After shuffle, runs of similar bytes become adjacent, and compressors like
LZ4 and Zstd achieve dramatically better ratios on the run-length-encoded
zeros.

### Speed Characteristics

- **Compression**: Fast when using LZ4 or BloscLZ as the internal compressor.
  The shuffle step adds some overhead but is typically cheap relative to the
  compression itself.
- **Decompression**: Fast. The unshuffle step is cheap (O(n) byte
  transposition), and the internal decompressor is fast.
- **Memory**: Blosc2 processes data in blocks (configurable via
  `blocksize`). Smaller blocks reduce memory usage but may reduce ratio.
- **Threading**: The C-Blosc2 library supports multi-threaded compression
  and decompression. ExCodecs' pure Rust implementation is currently
  single-threaded, though the `numthreads` parameter is accepted for forward
  compatibility.

### Ecosystem Adoption

- **Scientific computing**: Blosc2 is the primary compression format for
  PyTables, bcolz, and the newer python-blosc2 library.
- **Data formats**: The HDF5 library can use Blosc2 as a compression filter.
  Zarr supports Blosc2 as a compressor.
- **NumPy**: The blosc2 Python package provides NumPy-aware compression.
- **C-Blosc2**: The reference C library is used across the scientific Python
  ecosystem.

### Licensing

Blosc2 is licensed under **BSD 3-Clause**.

### Rust Ecosystem

ExCodecs uses a **pure Rust implementation** of the Blosc2 format rather than
binding to the C-Blosc2 library. This was a deliberate design decision.

| Aspect        | Status                                           |
|---------------|--------------------------------------------------|
| Implementation | Pure Rust in blosc2_codec.rs                    |
| Internal codecs| LZ4 (lz4_flex), Zstd (zstd), Snappy (snap)       |
| Shuffle       | Byte shuffle/unshuffle, bit shuffle/unshuffle   |
| Threading     | Single-threaded (numthreads parameter accepted)  |
| Coverage      | Core compress/decompress, all major options      |

### Why pure Rust instead of C-Blosc2 FFI?

1. **No C dependency**: C-Blosc2 depends on multiple internal libraries
   (libzstd, liblz4, etc.) and has a complex build system. Binding to it
   via FFI would add significant complexity to the NIF build process and
   complicate `rustler_precompiled` distribution.

2. **Code reuse**: The internal compress/decompress functions already exist
   in the NIF (LZ4 via `lz4_flex`, Zstd via `zstd`, Snappy via `snap`).
   Blosc2's meta-compression pattern just calls these with shuffled data.
   Reusing the existing Rust crates avoids code duplication.

3. **Format simplicity**: The Blosc2 header is only 16 bytes with a
   well-documented structure. Parsing and constructing the header in Rust
   takes approximately 100 lines, far less effort than binding C-Blosc2.

4. **Build reproducibility**: A pure Rust implementation compiles
   deterministically with the same toolchain. No system libraries, no
   pkg-config, no cmake.

5. **The shuffle is the value**: The primary benefit of Blosc2 is the byte
   and bit shuffle. The header format and passthrough behavior are trivial
   to implement. The shuffle routines are approximately 30-50 lines of Rust
   each.

**Limitations of the pure Rust approach**:

- No multi-threaded compression (the `numthreads` parameter is accepted but
  ignored). This can be added in a future release using Rayon or a similar
  Rust parallelism library.
- The bit shuffle implementation is a simplified version that handles common
  cases correctly but may differ from C-Blosc2 for edge cases.
- Some advanced C-Blosc2 features (lazy decompression, filters beyond
  shuffle, frames) are not yet supported.

### Tradeoffs

| Pro                                            | Con                                            |
|------------------------------------------------|------------------------------------------------|
| Dramatically better ratio on typed arrays      | Poor ratio on random/non-structured data       |
| Self-describing format (header includes meta) | Pure Rust impl lacks multithreading            |
| Supports multiple internal compressors        | Not a drop-in replacement for C-Blosc2 data    |
| Zero-overhead passthrough on incompressible   | Bit shuffle implementation simplified           |
| Pure Rust implementation (no C deps)           | numthreads parameter currently ignored         |
| Reuses existing Rust codec crates              | Some C-Blosc2 features not yet supported      |
| Excellent for numerical/array data             | Requires typesize knowledge for best results  |

---

## Comparison Table

| Property          | Zstd            | LZ4             | Snappy          | Bzip2           | Blosc2              |
|-------------------|-----------------|-----------------|-----------------|-----------------|----------------------|
| **Category**      | General-purpose  | General-purpose  | General-purpose  | General-purpose  | Meta-compressor      |
| **Ratio**         | High (2.8-3.8x) | Low (2.1x)      | Low (2.0x)      | Very high (3.3x)| Variable (1-15x)    |
| **Compress Speed**| Fast-slow*      | Very fast        | Very fast        | Slow             | Fast (depends on internal) |
| **Decomp Speed**  | Very fast       | Extremely fast   | Extremely fast   | Slow             | Fast (depends on internal) |
| **Memory (comp)** | 1-128 MB        | 16 KB            | 32 KB            | 1-8 MB           | Block-size dependent |
| **Configurability**| 22 levels      | 1-16 (HC variant)| None             | Block size 1-9   | cname, clevel, shuffle, typesize, blocksize |
| **Streaming?**    | Yes             | No (block only)  | No (raw only)    | Yes (block-based)| Yes (block-based)   |
| **Rust Backend**  | zstd (C FFI)    | lz4_flex (pure)  | snap (pure)      | bzip2 (C FFI)    | Pure Rust w/ existing crates |
| **Best For**      | Balanced use    | Real-time/lowest latency | Short-lived data | Archival/storage | Numerical arrays     |
| **License**       | BSD/GPL dual    | BSD 2-Clause     | BSD 3-Clause     | BSD-like         | BSD 3-Clause         |
| **ExCodecs Default**| Level 3       | Level 1          | N/A              | Block 9 / WF 30 | LZ4, level 5, byte shuffle |

*Zstd compression speed varies from very fast (level 1, ~520 MB/s) to slow
(level 22, ~4 MB/s). Decompression is consistently fast (~1.3 GB/s).

### Speed Comparison (Approximate, Silesia Corpus)

```
Compression Speed (MB/s, higher is better)
LZ4       ████████████████████████████████████████  ~700
Snappy    ██████████████████████████████████        ~550
Zstd-1    ███████████████████████████               ~520
Zstd-3    █████████████████████████                 ~430
Blosc2    ██████████████████████                    ~350*
Bzip2-9   ██                                        ~8

Decompression Speed (MB/s, higher is better)
LZ4       ████████████████████████████████████████  ~3000
Snappy    ████████████████████████████              ~1700
Zstd      ██████████████████████                    ~1300
Blosc2    ██████████████████                        ~1100*
Bzip2-9   █                                          ~25

Compression Ratio (higher is better)
Bzip2-9   █████████████████████████████████          ~3.3x
Zstd-22   ████████████████████████████████          ~3.8x
Zstd-3    ██████████████████████████                ~3.0x
Zstd-1    ████████████████████████                  ~2.8x
LZ4       ████████████████████                      ~2.1x
Snappy    ██████████████████                        ~2.0x

* Blosc2 speeds depend heavily on internal compressor and data typesize.
  Numbers shown use LZ4 as internal compressor with byte shuffle on float64.
```

### When to Use Each Codec

| Use Case                              | Recommended Codec | Reason                                 |
|---------------------------------------|--------------------|----------------------------------------|
| General-purpose compression            | Zstd level 3      | Best ratio/speed tradeoff              |
| Real-time/low-latency compression     | LZ4               | Fastest compression and decompression  |
| Short-lived data (RPC, caching)       | Snappy             | Minimal overhead, deterministic output |
| Archival/storage                      | Bzip2               | Highest ratio (or Zstd level 19-22)   |
| Numerical arrays (float64, int32)     | Blosc2              | Shuffle dramatically improves ratio   |
| Content-addressable storage           | Zstd               | Deterministic output at same level    |
| Maximum decompression speed           | LZ4                | 3+ GB/s decompression                  |
| Minimum memory usage                  | LZ4 or Snappy       | 16-32 KB compression buffer           |
| Streaming compression                 | Zstd                | Native streaming API                  |
| Binary data with known element size   | Blosc2              | Shuffle exploit element structure     |

---

## Decision Guide

```
                    What are you compressing?
                           |
              +------------+-----------+
              |                         |
       Numerical arrays?          General binary data?
       (float64, int32, etc.)    (text, JSON, arbitrary)
              |                         |
         Use Blosc2               What matters more?
         with byte shuffle              |
                              +---------+---------+
                              |                   |
                         Speed?              Ratio?
                              |                   |
                    Use LZ4              How much speed
                    (1 GB/s+)             are you willing
                                         to sacrifice?
                                              |
                                     +-------+-------+
                                     |               |
                                  Some             A lot
                                     |               |
                                Use Zstd-3       Use Bzip2
                                (fast + good     (best ratio,
                                 ratio)            slow speed)
```

For most use cases, **Zstd at level 3** is the recommended default. It
provides a strong compression ratio at high speed, and its decompression
performance is excellent. Switch to LZ4 only when latency is critical and
the ratio penalty is acceptable. Switch to Bzip2 only for archival use
where decompression speed is irrelevant. Use Blosc2 when your data is
numerical arrays and you can specify the element size.