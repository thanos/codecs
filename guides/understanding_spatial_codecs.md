# Understanding Spatial Codecs

This guide is a **domain primer** for ExCodecs' spatial category: what the
data is, what each Elixir type means, which file formats you encode to, and
when to use each piece. It is not a rendering tutorial - ExCodecs only moves
spatial data in and out of interchange formats.

## What problem does this solve?

You have 3D samples from a scanner, photogrammetry pipeline, or radiance-field
export, and you need to:

1. Represent them as Elixir structs in your BEAM process
2. Write them to a portable file (or bytes)
3. Read them back later - often into another tool that expects PLY or a compact
   binary container

Spatial codecs are the encode/decode layer for that. They do **not** draw
pixels, build meshes, or run a viewer.

## Point clouds vs Gaussian splats

These are two different ways to describe a scene as **many independent
samples**. Neither is a polygon mesh (no faces, no connectivity).

### Point cloud - a bag of dots

A **point cloud** is a list of positions in space. Each point is usually just
`(x, y, z)`. Optionally it can also carry:

- a color (what the scanner/camera saw)
- a surface normal (which way the surface faced)
- arbitrary attributes (intensity, classification, …)

Think of LiDAR returns, depth-camera frames, or the corners of a scanned room:
lots of floating dots, not triangles.

```text
        ·  ·
     ·     ·  ·
   ·   ·         ·     ← each · is one Point {x,y,z[,color,…]}
        ·    ·
           ·
```

In ExCodecs that bag is a `PointCloud` (the collection) of `Point` structs.

### Gaussian splat - a bag of fuzzy ellipsoids

A **3D Gaussian splat** (often from *3D Gaussian Splatting* research) is also
a sample in space, but instead of a hard dot it is a small **oriented blob**:

- **position** - where the blob is centered
- **scale** - how large it is along its local axes (an ellipsoid, not a sphere)
- **rotation** - how that ellipsoid is oriented (a quaternion)
- **opacity** - how solid / transparent it is
- **color** - base RGB (often the “DC” spherical-harmonic color)
- **SH** - optional higher-order **spherical harmonic** coefficients that
  encode view-dependent appearance (fancy lighting detail for renderers)

```text
        (~~)           ← one Gaussian: soft blob, not a hard vertex
     (~~~~)  (~~)
        (~~~~)
```

A renderer turns millions of these blobs into an image. **ExCodecs does not
render them** - it only stores and reloads the parameters so another program
(or a future library) can.

In ExCodecs that bag is a `GaussianCloud` of `Gaussian` structs.

| | Point cloud | Gaussian splat |
|--|-------------|----------------|
| Primitive | Hard sample (dot) | Soft ellipsoid (blob) |
| Typical source | LiDAR, depth cameras, photogrammetry points | Trained / exported radiance-field scenes |
| Looks like geometry? | Sparse surface samples | Appearance-oriented volume of blobs |
| ExCodecs types | `Point` / `PointCloud` | `Gaussian` / `GaussianCloud` |

## Pure Elixir - what “no NIFs” means

Yes: **today there is no Rust/NIF accelerator for spatial codecs**. Encode and
decode run in Elixir. Compression codecs (`:zstd`, `:lz4`, …) still use Rust
NIFs; spatial formats do not.

A common pattern is:

```elixir
{:ok, ply} = ExCodecs.Spatial.encode(cloud, format: :ply)
{:ok, packed} = ExCodecs.encode(:zstd, ply)   # NIF compresses the bytes
```

Spatial work stays on the BEAM; you optionally compress the resulting binary
with the registry codecs. A future release may add an optional Rust backend
for spatial encode/decode while keeping the same Elixir API.

## Domain types - what each one is for

```text
Point ──┐
        ├──► PointCloud ──► encode as :ply or :spatial_binary
Bounds ─┘         │
Metadata ─────────┘
Transform ────────┘   (optional pose of the whole cloud; not applied here)

Gaussian ──┐
           ├──► GaussianCloud ──► encode as :ply or :gsplat
Bounds / Metadata / Transform ─┘
```

### `Point` - one sample

One location in 3D, optionally colored / with a normal / with attributes.

```elixir
alias ExCodecs.Spatial.Point

Point.new(1.0, 2.0, 0.5,
  color: {255, 128, 0},
  normal: {0.0, 0.0, 1.0},
  attributes: %{"intensity" => 0.82}
)
```

**Use when:** you are building or iterating individual samples.

### `PointCloud` - the whole set (not a polygon)

A **collection** of points plus bookkeeping. It is **not** a mesh and **not**
a polygon. There are no edges or faces - only the list of points.

```elixir
alias ExCodecs.Spatial.{Point, PointCloud}

cloud =
  PointCloud.new([
    Point.new(0.0, 0.0, 0.0, color: {255, 0, 0}),
    Point.new(1.0, 0.0, 0.0, color: {0, 255, 0}),
    Point.new(0.0, 1.0, 0.0, color: {0, 0, 255})
  ])
```

`PointCloud` may also hold:

- `bounds` - axis-aligned box around the points (see below)
- `metadata` - free-form notes / comments
- `transform` - optional pose of the *entire* cloud (see below)

**Use when:** this is your unit of encode/decode for point data.

### `Bounds` - “how big is this cloud?”

An **axis-aligned bounding box** (AABB): min/max corners in XYZ. Useful for
culling, indexing, or quick spatial queries. It describes the extent of the
data; it is not the data itself.

```elixir
alias ExCodecs.Spatial.Bounds

Bounds.new({0.0, 0.0, 0.0}, {1.0, 1.0, 0.5})
```

**Use when:** you care about the cloud’s spatial footprint. Many codecs
recompute or omit bounds on the wire; keep them in the struct for app logic.

### `Gaussian` - one splat

One oriented ellipsoid with appearance parameters. The rotation/scale here
belong to **this splat**, not to a whole-scene pose.

```elixir
alias ExCodecs.Spatial.Gaussian

Gaussian.new({1.0, 2.0, 3.0},
  scale: {0.05, 0.02, 0.05},
  rotation: {1.0, 0.0, 0.0, 0.0},  # identity quaternion {w,x,y,z}
  opacity: 0.9,
  color: {0.8, 0.4, 0.1}
)
```

**Use when:** importing/exporting Gaussian-splat datasets.

### `GaussianCloud` - the whole splat set

Same idea as `PointCloud`, but for Gaussians.

**Use when:** this is your unit of encode/decode for splat data.

### `Transform` - pose of the *whole* cloud (not a splat)

A similarity transform (translation + quaternion rotation + **uniform** scale)
stored as **metadata**. ExCodecs does **not** apply it to points/Gaussians.

This is different from a Gaussian’s per-splat rotation/scale:

| | `Gaussian` rotation/scale | `Transform` |
|--|---------------------------|-------------|
| Applies to | One splat’s ellipsoid | The entire cloud (if you apply it) |
| Scale | Anisotropic `{sx,sy,sz}` | Uniform float |
| Applied by ExCodecs? | Stored as splat params | Stored only; you apply it |

**Use when:** a format or pipeline records “this cloud was captured with
sensor pose X” and you want to keep that alongside the samples.

### `Metadata` - comments and leftovers

String comments and a free-form map for application keys that are not geometry.

**Use when:** you need PLY header comments or app-specific tags to round-trip.

## Formats glossary - names that look similar but mean different things

Three layers of vocabulary get mixed up. Keep them separate:

| Kind | Examples | What it is |
|------|----------|------------|
| **Domain concept** | point cloud, **splat** / Gaussian splat | The *kind of 3D data* in memory |
| **Format atom** | `:ply`, `:spatial_binary`, `:gsplat` | What you pass to `ExCodecs.Spatial.encode/decode` |
| **On-wire magic / file type** | PLY text/binary, **`EXCP`**, **`GSPL`** | Bytes on disk / on the network |

```text
In memory                         On the wire
─────────                         ───────────
PointCloud      ──format: :ply──►           *.ply  (PLY header + body)
PointCloud      ──format: :spatial_binary──► magic "EXCP" …
GaussianCloud   ──format: :ply──►           *.ply  (Gaussian property names)
GaussianCloud   ──format: :gsplat──►        magic "GSPL" …
```

### “Splat” (domain concept - not a format)

**Splat** is short for **Gaussian splat**: one soft 3D ellipsoid sample (see
above). A **splat cloud** is many of them (`GaussianCloud`).

There is **no** `format: :splat`. To store splats you choose either:

- `:ply` - portable interchange (Gaussian PLY properties), or
- `:gsplat` - ExCodecs’ compact binary (on-wire magic **`GSPL`**)

### PLY / `format: :ply` - the portable interchange format

**PLY** (Polygon File Format / Stanford Triangle Format) is a **decades-old,
widely supported** 3D file format. A PLY file always starts with a readable
header, then a body of per-vertex (or per-face) properties.

Despite “polygon” in the name, PLY is routinely used as a **point list** -
just vertices with `x y z` (and maybe colors), no faces at all. Research and
Gaussian-splat tools also stuff splat fields into the same PLY property
mechanism (`f_dc_*`, `opacity`, `scale_*`, `rot_*`, `f_rest_*`).

**What it’s for**

- Hand files to MeshLab, CloudCompare, Blender, Python/`open3d`, research code
- Debug by opening ASCII PLY in a text editor
- Exchange with people / tools that have never heard of ExCodecs

**What you write in Elixir**

```elixir
ExCodecs.Spatial.encode(cloud, format: :ply)
ExCodecs.Spatial.encode(cloud, format: :ply, ply_format: :binary_le)
ExCodecs.Spatial.encode(gaussians, format: :ply)  # Gaussian property names
```

**Trade-offs**

- Universal tooling, human-inspectable (ASCII)
- Larger / slower than EXCP/GSPL; schema is flexible but verbose
- Works for **both** point clouds and Gaussian clouds

PLY options (after `format: :ply`):

- `:ply_format` or `:format` - `:ascii` (default), `:binary` / `:binary_le`,
  or `:binary_be` (**PLY body encoding**, not the Spatial format atom)
- `:comments` - header comments
- `:as` - on decode: `:auto`, `:point_cloud`, or `:gaussian_cloud`

Tiny ASCII PLY (three colored points):

```text
ply
format ascii 1.0
element vertex 3
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
end_header
0 0 0 255 0 0
1 0 0 0 255 0
0 1 0 0 0 255
```

### EXCP / `format: :spatial_binary` - compact point-cloud bytes

**EXCP** is ExCodecs’ **own** little-endian binary container for point clouds.
The name is the 4-byte magic at the start of the payload (`"EXCP"`).

**`:spatial_binary`** is the **Elixir format atom** you pass to the API.
Same thing, two names:

| You say in code | Bytes begin with | Holds |
|-----------------|------------------|-------|
| `format: :spatial_binary` | `EXCP` | `PointCloud` only |

**What it’s for**

- Store or ship point clouds **inside your own system** (DB blob, message,
  object store) when PLY would be wasteful
- Fast encode/decode with a fixed record layout (xyz + optional color/alpha/normals)
- Pair with `:zstd` / `:lz4` afterward if you want compression

**What it’s not for**

- Giving files to MeshLab / Blender (they don’t speak EXCP)
- Storing Gaussian splats (use `:gsplat` or Gaussian `:ply`)
- Carrying arbitrary per-point string attributes, cloud metadata, or transforms
  on the wire (v1 drops those - see [Spatial wire formats](../docs/spatial_formats.md))

```elixir
{:ok, excp} = ExCodecs.Spatial.encode(point_cloud, format: :spatial_binary)
# excp starts with <<"EXCP", ...>>
{:ok, cloud} = ExCodecs.Spatial.decode(excp, format: :spatial_binary)
```

### GSPL / `format: :gsplat` - compact Gaussian-splat bytes

**GSPL** is ExCodecs’ **own** little-endian binary container for Gaussian
clouds. Magic bytes: `"GSPL"`.

**`:gsplat`** is the format atom. Again: atom in Elixir, magic on the wire.

| You say in code | Bytes begin with | Holds |
|-----------------|------------------|-------|
| `format: :gsplat` | `GSPL` | `GaussianCloud` only |

**What it’s for**

- Compact storage/transfer of splat parameters (position, DC color, opacity,
  scale, rotation, optional SH rest coefficients)
- Internal pipelines where PLY Gaussian dumps are too fat

**What it’s not for**

- Point clouds (use `:spatial_binary` or `:ply`)
- Universal desktop 3D tools (use Gaussian `:ply` for interchange)
- Preserving arbitrary per-Gaussian metadata maps on the wire (v1 drops them)

```elixir
{:ok, gspl} = ExCodecs.Spatial.encode(gaussian_cloud, format: :gsplat)
# gspl starts with <<"GSPL", ...>>
{:ok, cloud} = ExCodecs.Spatial.decode(gspl, format: :gsplat)
```

### Quick chooser

| Goal | Use |
|------|-----|
| Share points with other 3D software | `:ply` |
| Share Gaussians with research / splat tools | `:ply` (Gaussian properties) |
| Compact points inside *your* stack | `:spatial_binary` → optional `:zstd` |
| Compact Gaussians inside *your* stack | `:gsplat` → optional `:zstd` |
| “I heard splat / EXCP / GSPL” | splat = data kind; EXCP/GSPL = our binary containers |

Wire layouts and schema rules are frozen in
[Spatial wire formats](../docs/spatial_formats.md).

Stream helpers today **materialize** the full payload, then enumerate. Prefer
explicit `source: :file` or `source: :binary`.

## Why a separate `ExCodecs.Spatial` API?

Compression codecs map **binary → binary** (`ExCodecs.encode(:zstd, bin)`).
Spatial codecs map **structs ↔ formats**. Overloading one function for both
shapes is confusing, so spatial work goes through `ExCodecs.Spatial`.

Both categories share the catalog (`ExCodecs.available_codecs(:spatial)`),
tagged `{:ok, _}` / `{:error, %ExCodecs.Error{}}` results, and discovery
metadata. Calling `ExCodecs.encode(:ply, …)` intentionally fails with guidance
to use the spatial API.

## End-to-end examples

### Point cloud → PLY → back

```elixir
alias ExCodecs.Spatial.{Point, PointCloud}

cloud =
  PointCloud.new([
    Point.new(0.0, 0.0, 0.0, color: {255, 0, 0}),
    Point.new(1.0, 1.0, 0.0, color: {0, 255, 0})
  ])

{:ok, ply} = ExCodecs.Spatial.encode(cloud, format: :ply)
{:ok, decoded} = ExCodecs.Spatial.decode(ply, format: :ply)

ExCodecs.Spatial.available_formats()
ExCodecs.codec_info(:ply)
```

### Compact binary for points, then compress

```elixir
{:ok, excp} = ExCodecs.Spatial.encode(decoded, format: :spatial_binary)
{:ok, packed} = ExCodecs.encode(:zstd, excp)
{:ok, excp2} = ExCodecs.decode(:zstd, packed)
{:ok, ^decoded} = ExCodecs.Spatial.decode(excp2, format: :spatial_binary)
```

### Load a sample from the package

```elixir
path = Application.app_dir(:ex_codecs, "priv/examples/spatial/cube_corners.ply")
{:ok, cloud} = ExCodecs.Spatial.decode(File.read!(path), format: :ply)

path = Application.app_dir(:ex_codecs, "priv/examples/spatial/two_gaussians.ply")
{:ok, gaussians} = ExCodecs.Spatial.decode(File.read!(path), format: :ply)
```

## Out of scope

ExCodecs does **not** provide:

- a viewer / rasterizer for points or Gaussians
- mesh topology (faces, edges)
- spatial indexes, LOD, or true progressive streaming
- supercompressed containers such as SOG

Those belong in higher-level libraries built on top of these codecs.
