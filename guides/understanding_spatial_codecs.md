# Understanding Spatial Codecs

ExCodecs includes a spatial **category module** (`ExCodecs.Spatial`) for
continuous and geometric data: point clouds and Gaussian splats. These codecs
map between structured Elixir types and interchange formats. They do not render
or use NIFs — pure Elixir.

The top-level registry API (`ExCodecs.encode(codec, binary)`) is **not** used
for spatial data. Always call `ExCodecs.Spatial.*`.

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
an in-memory list). Pass `source: :file` when the argument is a filesystem path.

## API

Spatial is a **category module** (like `ExCodecs.Compression`). Prefer it over
the top-level registry API for all spatial work:

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
```

`ExCodecs.encode/3` and `ExCodecs.decode/3` remain **codec atom + binary** only
(registry compression codecs). Passing a `PointCloud` or `format: :ply` there
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
