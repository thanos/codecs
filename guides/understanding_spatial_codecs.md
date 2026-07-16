# Understanding Spatial Codecs

Spatial is a category in the ExCodecs framework for continuous and geometric
data: point clouds and Gaussian splats. These codecs map between structured
Elixir types and interchange formats. They do not render or use NIFs — pure
Elixir.

ExCodecs uses specialized category APIs because data shapes differ. The
top-level registry API handles binary→binary codecs; spatial struct↔format work
uses `ExCodecs.Spatial.*`. Both follow the framework's tagged-result and
structured-error conventions, and both are registered in the shared codec
catalog.

## Domain Types

| Type | Role |
|------|------|
| `ExCodecs.Spatial.Point` | XYZ (+ optional color, normal, attributes) |
| `ExCodecs.Spatial.PointCloud` | Collection of points + bounds/metadata |
| `ExCodecs.Spatial.Gaussian` | Position, rotation, scale, opacity, color, SH |
| `ExCodecs.Spatial.GaussianCloud` | Collection of Gaussians |
| `ExCodecs.Spatial.Bounds` | Axis-aligned bounding box |
| `ExCodecs.Spatial.Transform` | Translation / rotation / scale metadata |
| `ExCodecs.Spatial.Metadata` | Comments and free-form entries |

## Formats

| Format atom | Module | Use |
|-------------|--------|-----|
| `:ply` | `ExCodecs.Spatial.Codec.PLY` | ASCII/binary PLY, Gaussian PLY |
| `:spatial_binary` | `ExCodecs.Spatial.Codec.Binary` | Compact `EXCP` point clouds |
| `:gsplat` | `ExCodecs.Spatial.Codec.Gsplat` | Compact `GSPL` Gaussians |

PLY encode options (after Spatial `format: :ply` is selected):

- `:ply_format` or `:format` — PLY wire encoding: `:ascii` (default),
  `:binary` / `:binary_le`, or `:binary_be` (not the Spatial format atom)
- `:comments` — header comments
- `:as` — on decode: `:auto`, `:point_cloud`, or `:gaussian_cloud`
- `:source` — for streams: `:auto` (default), `:file`, or `:binary`

Spatial stream helpers materialize the full payload today (lazy enumeration of
an in-memory list). Prefer explicit `source: :file` or `source: :binary`.
With `:auto`, a binary is opened as a path only when it looks path-like (under
4 KiB, no `ply`/`EXCP`/`GSPL` magic, separator or known extension) **and** is a
regular file. Files without separators/extensions are not auto-detected.

Wire layouts for EXCP/GSPL/PLY schema rules are frozen in
[Spatial wire formats](../docs/spatial_formats.md).

## API

Use the spatial category API for all spatial work:

```elixir
alias ExCodecs.Spatial.{Point, PointCloud}

cloud =
  PointCloud.new([
    Point.new(0.0, 0.0, 0.0, color: {255, 0, 0}),
    Point.new(1.0, 1.0, 0.0, color: {0, 255, 0})
  ])

{:ok, ply} = ExCodecs.Spatial.encode(cloud, format: :ply)
{:ok, decoded} = ExCodecs.Spatial.decode(ply, format: :ply)

ExCodecs.Spatial.stream_decode(ply, format: :ply)
|> Enum.take(2)

{:ok, bin} =
  ExCodecs.Spatial.stream_encode(decoded.points, format: :spatial_binary)

ExCodecs.Spatial.available_formats()
ExCodecs.Spatial.supports?(:ply)
ExCodecs.available_codecs(:spatial)
ExCodecs.codec_info(:ply)
```

`ExCodecs.encode/3` and `ExCodecs.decode/3` remain **binary-interface codec atom
+ binary** only. Spatial atoms are discoverable there, but operation dispatch
returns a clear error pointing at this module.

## Examples

Sample PLY files ship in `priv/examples/spatial/`:

- `cube_corners.ply` — colored XYZ point cloud
- `two_gaussians.ply` — minimal Gaussian PLY

```elixir
path = Application.app_dir(:ex_codecs, "priv/examples/spatial/cube_corners.ply")
{:ok, cloud} = ExCodecs.Spatial.decode(File.read!(path), format: :ply)
```

## Out of Scope

Supercompressed SOG, spatial indexes, LOD hierarchies, and progressive
streaming belong in future libraries built on top of ExCodecs (e.g. `ex_sog`).
