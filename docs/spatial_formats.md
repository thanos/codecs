# Spatial wire formats (v0.2.0 freeze)

This document freezes the on-wire layouts used by `ExCodecs.Spatial` since
**v0.2.0**. The Rust spatial acceleration shipped in **v0.2.3** must produce
**byte-compatible** output for these formats (verified by property tests).
There is **no CRC / checksum** in v1; integrity is the caller's responsibility.

Attribute keys on points are **strings** after construction / decode. Prefer string
keys when building clouds for cross-backend compatibility.

## One framework, specialized category APIs

| Category | Entry point | Discovery |
|----------|-------------|-----------|
| Registry binary codecs (`:zstd`, …) | `ExCodecs.encode/3`, `decode/3` | `available_codecs(:compression)` |
| Spatial domain codecs | `ExCodecs.Spatial.encode/2`, `decode/2` | `available_codecs(:spatial)` or `ExCodecs.Spatial.available_formats/0` |

Both categories belong to the ExCodecs framework and share its tagged-result
and error conventions. Their entry points differ because registry codecs map
binary↔binary, while spatial codecs map domain structs↔formats.

Spatial formats (`:ply`, `:spatial_binary`, `:gsplat`) are entries in the same
ETS-backed catalog as compression codecs. Their metadata has
`category: :spatial` and `interface: :spatial`; that interface marker keeps
operation dispatch on `ExCodecs.Spatial` rather than the binary API.

## PLY (`format: :ply`)

Standard PLY interchange (ASCII or binary little/big endian). Gaussian PLY uses
common property names (`f_dc_*`, `opacity`, `scale_*`, `rot_*`, `f_rest_*`).

Encode options (after Spatial selects `:ply`):

- `:ply_format` or `:format` — `:ascii` (default), `:binary` / `:binary_le`, `:binary_be`
- `:comments` — header comments
- `:as` — decode as `:auto`, `:point_cloud`, or `:gaussian_cloud`

### Schema promotion

If **any** point in a cloud has color / alpha / normals, the schema includes those
properties for **all** points. Missing values are defaulted (RGB `0`, alpha `255`,
normal `{0,0,0}`). Mixed optional fields therefore round-trip with defaults filled in.

### Streaming

- **EXCP / GSPL / PLY + `source: :file`** (or `:auto` path detection): header
  then one record/vertex at a time from disk (bounded memory). Binary PLY uses
  a fixed property stride; ASCII PLY reads lines.
- In-memory binaries use **chunked Rust unpack** when the spatial NIF is
  loaded; otherwise they materialize through `decode/2`.
- `stream_encode` still collects the enumerable, then encodes once.
- `encode_to_file/3` with an explicit `:schema` streams EXCP/GSPL to disk
  (placeholder header + seek-back count; chunked Rust pack when available).
  Without `:schema`, encode then write.
- Pass `accel: false` on encode/decode/stream helpers to force pure Elixir.

Prefer explicit `source: :file` or `source: :binary` when the argument is
ambiguous (`:binary` is the default). File streams prefer mmap + DirtyCpu
unpack when Accel is available. Do not truncate a mapped file while a stream
is live (SIGBUS risk).

`:auto` (opt-in) treats a binary as a path only when it looks path-like (under
4 KiB, no `ply`/`EXCP`/`GSPL` magic, and contains `/` or `\` or ends with
`.ply`/`.excp`/`.gspl`/`.bin`) **and** `File.regular?/1` is true. Edge cases:

- A real file with no separator/extension is **not** auto-opened.
- A short binary containing `/` that happens to be a regular file path **is** opened.

## EXCP — `:spatial_binary` (version 1)

Little-endian compact point clouds.

```
Offset  Size  Field
0       4     magic "EXCP"
4       2     version u16 LE (= 1)
6       2     flags u16 LE
8       8     count u64 LE
16      …     records
```

**Flags**

| Bit | Meaning |
|-----|---------|
| 0   | color (RGB u8 × 3) |
| 1   | alpha (RGBA; implies color bytes include alpha) |
| 2   | normals (f32 × 3) |

**Record order:** `x,y,z` as `f32` LE, then optional color bytes, then optional
normals. Flags are global for the file; points missing a promoted field are
zero-filled (alpha default 255).

**Not stored:** generic attributes, bounds, transform, metadata. Trailing bytes
after `count` records are ignored. Truncation yields `:invalid_data` /
`:truncated_input` as implemented.

**Streaming:** `stream_decode` with `source: :file` reads the 16-byte header,
then each record via `IO.binread/2` (bounded memory). In-memory binaries use
chunked Rust unpack when the spatial NIF is loaded; otherwise they materialize
through `decode/2`. `stream_encode_to_file/3` requires `:schema`
(e.g. `schema: [:color]`) and patches the count after writing records.

## GSPL — `:gsplat` (version 1)

Little-endian compact Gaussian clouds.

```
Offset  Size  Field
0       4     magic "GSPL"
4       2     version u16 LE (= 1)
6       2     flags u16 LE (bit0 set when SH rest present)
8       8     count u64 LE
16      2     sh_rest u16 LE (floats of SH rest per Gaussian; 0 if none)
18      …     records
```

**Record (always):** 14 × `f32` LE —

1. position XYZ (3)
2. DC color RGB (3) — maps to `Gaussian.color`
3. opacity (1)
4. scale XYZ (3)
5. rotation quaternion WXYZ (4)

Then `sh_rest` × `f32` LE (shared length for all Gaussians; shorter lists padded
with zeros on encode).

**Not stored:** per-Gaussian metadata maps, cloud metadata. Flags on decode are
currently informational; `sh_rest` count in the header is authoritative.

**Streaming:** `stream_decode` with `source: :file` reads the 18-byte header,
then each record via `IO.binread/2` (bounded memory). In-memory binaries use
chunked Rust unpack when the spatial NIF is loaded; otherwise they materialize
through `decode/2`. `stream_encode_to_file/3` requires `:schema`
(e.g. `schema: []` or `schema: [sh_rest: 6]`) and patches the count after
writing records.

## Integrity

v1 formats have **no checksum**. For integrity, wrap payloads with a registry
codec (e.g. compress after encode) or store an external hash.
