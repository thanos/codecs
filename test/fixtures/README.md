# Compression wire-format goldens

These fixtures pin ExCodecs' pure-Rust backends against reference wire bytes.

| Codec | Tool | Notes |
|-------|------|--------|
| `zstd/` | `zstd(1)` CLI | Standard Zstandard frame |
| `bzip2/` | `bzip2(1)` CLI | Standard bzip2 stream |
| `lz4/` | `lz4_flex::compress_prepend_size` | Size-prepended block (not LZ4 frame) |
| `snappy/` | `snap::raw` | Raw Snappy block (not framing format) |

Regenerate (from repo root):

```sh
# zstd + bzip2
printf 'payload...' > test/fixtures/zstd/level3.src
zstd -3 -f -o test/fixtures/zstd/level3.bin test/fixtures/zstd/level3.src
cp test/fixtures/zstd/level3.src test/fixtures/bzip2/default.src
bzip2 -c test/fixtures/bzip2/default.src > test/fixtures/bzip2/default.bin

# lz4 + snappy (uses the same crates as the NIF)
cd native/ex_codecs_native
# one-shot: cargo run --example gen_goldens  (see prior generation)
```
