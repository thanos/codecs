defmodule ExCodecs.Spatial do
  @moduledoc """
  Spatial category API for point clouds and Gaussian splats.

  ExCodecs is one codec framework with entry points specialized by data shape.
  Binary→binary registry codecs use `ExCodecs.encode/3` / `decode/3`; spatial
  codecs map the domain structs below to and from interchange formats through
  this module.

  ## Domain types

  | Struct | Role |
  |--------|------|
  | `ExCodecs.Spatial.Point` | XYZ (+ color, normal, attributes) |
  | `ExCodecs.Spatial.PointCloud` | List of points + bounds/metadata |
  | `ExCodecs.Spatial.Gaussian` | Single splat primitive |
  | `ExCodecs.Spatial.GaussianCloud` | List of Gaussians |
  | `ExCodecs.Spatial.Bounds` | Axis-aligned bounding box |
  | `ExCodecs.Spatial.Transform` | Translation/rotation/scale metadata |
  | `ExCodecs.Spatial.Metadata` | Comments and free-form entries |

  ## Formats

  | Atom | Module | Input type |
  |------|--------|------------|
  | `:ply` | `ExCodecs.Spatial.Codec.PLY` | PointCloud or GaussianCloud |
  | `:spatial_binary` | `ExCodecs.Spatial.Codec.Binary` | PointCloud (`EXCP`) |
  | `:gsplat` | `ExCodecs.Spatial.Codec.Gsplat` | GaussianCloud (`GSPL`) |

  Spatial formats are registered in the shared codec catalog. Discover all
  entries with `ExCodecs.available_codecs/0`, or only this category with
  `available_formats/0`.

  ## Quick start

      alias ExCodecs.Spatial.{Point, PointCloud}

      cloud =
        PointCloud.new([
          Point.new(0.0, 0.0, 0.0, color: {255, 0, 0}),
          Point.new(1.0, 1.0, 1.0, color: {0, 255, 0})
        ])

      {:ok, ply} = ExCodecs.Spatial.encode(cloud, format: :ply)
      {:ok, decoded} = ExCodecs.Spatial.decode(ply, format: :ply)

  ## Streaming note

  EXCP (`:spatial_binary`) and GSPL (`:gsplat`) **file** sources stream
  record-by-record from disk. PLY and in-memory binaries still materialize,
  then enumerate. Prefer `source: :file` for large EXCP/GSPL paths, or
  `source: :binary` for payloads. See `docs/spatial_formats.md` for `:auto`
  path heuristics and wire-format layouts.
  """

  alias ExCodecs.{CodecRegistry, Error}
  alias ExCodecs.Spatial.{GaussianCloud, PointCloud}
  @formats [:ply, :spatial_binary, :gsplat]

  @doc """
  Lists the spatial formats accepted by this module.

  ## Arguments

  This function takes no arguments.

  ## Returns

  The list `[:ply, :spatial_binary, :gsplat]`, where `:ply` supports point and
  Gaussian clouds, `:spatial_binary` supports point clouds, and `:gsplat`
  supports Gaussian clouds.

  ## Raises / exceptions

  This function does not raise.

  ## Examples

      iex> ExCodecs.Spatial.available_formats()
      [:ply, :spatial_binary, :gsplat]
  """
  @spec available_formats() :: [atom()]
  def available_formats do
    available = CodecRegistry.available_codecs(:spatial)
    preferred = Enum.filter(@formats, &(&1 in available))
    preferred ++ Enum.reject(available, &(&1 in @formats))
  end

  @doc """
  Tests whether an atom names a supported spatial format.

  ## Arguments

    * `format` (`atom()`) — the candidate format name.

  ## Returns

  `true` for `:ply`, `:spatial_binary`, or `:gsplat`; otherwise `false`.

  ## Raises / exceptions

  Raises `FunctionClauseError` when `format` is not an atom because the public
  function is guarded with `is_atom/1`.

  ## Examples

      iex> ExCodecs.Spatial.supports?(:ply)
      true

      iex> ExCodecs.Spatial.supports?(:sog)
      false
  """
  @spec supports?(atom()) :: boolean()
  def supports?(format) when is_atom(format) do
    case CodecRegistry.codec_info(format) do
      {:ok, %{category: :spatial, interface: :spatial, module: module}} -> module != nil
      _ -> false
    end
  end

  @doc """
  Encodes a point cloud or Gaussian cloud in a selected spatial format.

  ## Arguments

    * `data` (`PointCloud.t() | GaussianCloud.t()`) — a point cloud for
      `:ply` or `:spatial_binary`, or a Gaussian cloud for `:ply` or `:gsplat`.
    * `opts` (`keyword()`) — options passed to the selected codec:
      * `:format` — spatial container: `:ply` (default), `:spatial_binary`, or
        `:gsplat`. This key is removed before codec dispatch.
      * for PLY, `:ply_format` selects `:ascii`, `:binary`, `:binary_le`, or
        `:binary_be`; `:comments` overrides metadata comments.
      * the binary and GSPL codecs currently ignore remaining options.

  `%PointCloud{}` contains a list of `%Point{}` values; `%GaussianCloud{}`
  contains a list of `%Gaussian{}` values. See the selected codec for the
  fields represented on the wire.

  ## Returns

    * `{:ok, payload}` where `payload` is the encoded `binary()`.
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      supported cloud, the cloud type does not match the format, a PLY value
      cannot be encoded, or a malformed struct causes PLY encoding to fail.
    * `{:error, %ExCodecs.Error{reason: :unsupported_codec}}` when `:format`
      is not one of the supported spatial format atoms.

  ## Raises / exceptions

  Validation errors above are returned. `Keyword.pop/3` raises
  `FunctionClauseError` when `opts` is not a proper keyword list. EXCP and GSPL
  encoding can also raise exceptions such as `MatchError`, `FunctionClauseError`,
  or `ArgumentError` when callers manually construct malformed cloud/member
  structs whose tuple shapes or numeric values violate the documented struct
  contracts. PLY catches encoding exceptions and returns `:invalid_data`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> cloud = PointCloud.new([Point.new(1.0, 2.0, 3.0)])
      iex> {:ok, bin} = ExCodecs.Spatial.encode(cloud, format: :ply)
      iex> is_binary(bin)
      true
  """
  @spec encode(PointCloud.t() | GaussianCloud.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t()}
  def encode(data, opts \\ [])

  def encode(%PointCloud{} = data, opts) do
    {format, codec_opts} = Keyword.pop(opts, :format, :ply)

    if format == :gsplat do
      {:error,
       Error.new(:invalid_data,
         codec: :gsplat,
         message: "GSPLAT format requires a GaussianCloud"
       )}
    else
      with {:ok, module} <- spatial_codec(format) do
        module.encode(data, codec_opts)
      end
    end
  end

  def encode(%GaussianCloud{} = data, opts) do
    {format, codec_opts} = Keyword.pop(opts, :format, :ply)

    if format == :spatial_binary do
      {:error,
       Error.new(:invalid_data,
         codec: :spatial_binary,
         message: "spatial_binary format requires a PointCloud"
       )}
    else
      with {:ok, module} <- spatial_codec(format) do
        module.encode(data, codec_opts)
      end
    end
  end

  def encode(_, _) do
    {:error,
     Error.new(:invalid_data,
       message: "Spatial encode expects a PointCloud or GaussianCloud"
     )}
  end

  @doc """
  Decodes a spatial payload into a point cloud or Gaussian cloud.

  ## Arguments

    * `data` (`binary()`) — a complete encoded payload.
    * `opts` (`keyword()`) — decode options:
      * `:format` — `:ply` (default), `:spatial_binary`, or `:gsplat`.
      * `:as` — PLY interpretation: `:auto` (default), `:point_cloud`, or
        `:gaussian_cloud`. In `:auto`, Gaussian property names select a
        `%GaussianCloud{}`; other vertex schemas select a `%PointCloud{}`.

  ## Returns

    * `{:ok, %PointCloud{}}` for EXCP or point-oriented PLY.
    * `{:ok, %GaussianCloud{}}` for GSPL or Gaussian-oriented PLY.
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` for a non-binary
      input, bad magic/version, malformed or unsupported PLY header/property,
      missing/truncated records, or otherwise invalid payload.
    * `{:error, %ExCodecs.Error{reason: :unsupported_codec}}` for an unknown
      `:format`.

  ## Raises / exceptions

  Payload validation failures are returned. `Keyword.pop/3` and codec option
  access raise `FunctionClauseError` when `opts` is not a proper keyword list.
  For PLY, an unsupported `:as` value has no matching interpretation clause
  and raises `CaseClauseError`; malformed ASCII rows can also surface
  constructor/shape exceptions instead of an error tuple.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.encode(PointCloud.new([Point.new(0.0, 0.0, 1.0)]), format: :ply)
      iex> {:ok, %PointCloud{points: points}} = ExCodecs.Spatial.decode(bin, format: :ply)
      iex> length(points)
      1
  """
  @spec decode(binary(), keyword()) ::
          {:ok, PointCloud.t() | GaussianCloud.t()} | {:error, Error.t()}
  def decode(data, opts \\ [])

  def decode(data, opts) when is_binary(data) do
    {format, codec_opts} = Keyword.pop(opts, :format, :ply)

    with {:ok, module} <- spatial_codec(format) do
      module.decode(data, codec_opts)
    end
  end

  def decode(_, _) do
    {:error, Error.new(:invalid_data, message: "Spatial decode expects a binary")}
  end

  defp spatial_codec(format) do
    case CodecRegistry.lookup(format) do
      {:ok, {module, :spatial, %{interface: :spatial}}} when module != nil ->
        {:ok, module}

      {:ok, {nil, :spatial, %{interface: :spatial}}} ->
        {:error, Error.new(:codec_unavailable, codec: format)}

      _ ->
        {:error, Error.new(:unsupported_codec, codec: format)}
    end
  end

  @doc """
  Returns an enumerable over points or Gaussians decoded from a path or binary.

  Despite the name, decoding currently materializes the complete payload and
  decoded cloud before yielding elements.

  ## Arguments

    * `source` (`Path.t() | binary()`) — a filesystem path or encoded payload.
      Since paths are binaries in Elixir, use `source: :file` to force path
      interpretation or `source: :binary` to force payload interpretation.
    * `opts` (`keyword()`) — requires `:format` (`:ply`,
      `:spatial_binary`, or `:gsplat`). `:source` may be `:auto` (default),
      `:file`, or `:binary`; remaining options go to the selected decoder.

  ## Returns

  An `Enumerable.t()` yielding `%Point{}` or `%Gaussian{}`. On failure it
  yields exactly one `{:error, %ExCodecs.Error{}}` element:

    * `reason: :invalid_options` when `:format` is missing.
    * `reason: :unsupported_codec` for an unknown format.
    * `reason: :io_error` when a forced or auto-detected file cannot be read.
    * `reason: :invalid_data` for malformed, unsupported, or truncated data.

  ## Raises / exceptions

  Missing `:format` is represented by an error element. Keyword operations
  raise `FunctionClauseError` for a non-keyword `opts`. PLY only accepts a
  binary/path source and raises `FunctionClauseError` otherwise. Invalid
  `:source` values can raise `CaseClauseError`. Exceptions documented by the
  selected decoder can occur while the returned stream is enumerated.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.encode(PointCloud.new([Point.new(1.0, 0.0, 0.0)]), format: :ply)
      iex> list = ExCodecs.Spatial.stream_decode(bin, format: :ply) |> Enum.to_list()
      iex> match?([%Point{}], list)
      true
  """
  @spec stream_decode(Path.t() | binary(), keyword()) :: Enumerable.t()
  def stream_decode(source, opts \\ []) do
    ExCodecs.Spatial.Stream.decode(source, opts)
  end

  @doc """
  Encodes an enumerable of points or Gaussians to one spatial payload.

  The enumerable is fully collected so the codec can write the element count.
  A non-empty enumerable is classified by its first element and must contain
  valid values of that same struct type. An empty enumerable becomes an empty
  point cloud for PLY/EXCP or an empty Gaussian cloud for GSPL.

  ## Arguments

    * `enumerable` (`Enumerable.t()`) — `%Point{}` or `%Gaussian{}` elements.
    * `opts` (`keyword()`) — requires `:format` (`:ply`,
      `:spatial_binary`, or `:gsplat`); remaining options are the same as
      `encode/2`.

  ## Returns

    * `{:ok, payload}` where `payload` is a `binary()`.
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` when `:format` is
      missing.
    * `{:error, %ExCodecs.Error{reason: :unsupported_codec}}` for an unknown
      format.
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when the first element
      is not a point/Gaussian, is an error tuple, the primitive type does not
      match the format, or codec encoding fails.

  ## Raises / exceptions

  Missing `:format` is returned as `:invalid_options`. `Enum.to_list/1` may
  raise `Protocol.UndefinedError` for a non-enumerable or propagate an
  exception raised by the enumerable. Keyword operations raise
  `FunctionClauseError` for invalid `opts`; malformed member structs may raise
  the codec exceptions described by `encode/2`.

  ## Examples

      iex> alias ExCodecs.Spatial.Point
      iex> {:ok, bin} = ExCodecs.Spatial.stream_encode([Point.new(0.0, 0.0, 0.0)], format: :spatial_binary)
      iex> is_binary(bin)
      true
  """
  @spec stream_encode(Enumerable.t(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def stream_encode(enumerable, opts \\ []) do
    ExCodecs.Spatial.Stream.encode(enumerable, opts)
  end
end
