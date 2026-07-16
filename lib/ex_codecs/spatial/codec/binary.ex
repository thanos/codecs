defmodule ExCodecs.Spatial.Codec.Binary do
  @moduledoc """
  Compact little-endian binary format for point clouds.

  ## Layout

      magic:   "EXCP" (4 bytes)
      version: u16 LE = 1
      flags:   u16 LE  (bit0=color, bit1=alpha, bit2=normal)
      count:   u64 LE
      records: count × record

  Each record always has `x,y,z` as `f32`. Optional `rgb`/`rgba` as `u8`
  and normals as `f32` follow according to flags.

  Generic attributes are not stored in this format — use PLY for that.
  """

  alias ExCodecs.Error
  alias ExCodecs.Spatial.{Point, PointCloud, Metadata}

  @magic "EXCP"
  @version 1

  @flag_color 0b001
  @flag_alpha 0b010
  @flag_normal 0b100

  @doc """
  Encodes a point cloud in the EXCP version 1 binary format.

  The 16-byte header is `"EXCP"`, version `u16` little-endian, global flags
  `u16` little-endian, and point count `u64` little-endian. Each record starts
  with three little-endian `f32` coordinates. Global flag bits then add RGB
  (3 bytes), RGBA (4 bytes; alpha takes precedence), and/or three little-endian
  `f32` normal components to every record.

  Flags are selected from the whole cloud. Consequently, points missing an
  optional field are zero-filled (missing alpha is 255). Point attributes,
  cloud bounds, transform, and metadata are not represented.

  ## Arguments

    * `data` (`PointCloud.t()`) — a cloud whose `points` are valid `%Point{}`
      structs with numeric coordinates, optional `{r, g, b}` or
      `{r, g, b, a}` color, and optional `{nx, ny, nz}` normal.
    * `opts` (`keyword()`) — reserved and currently ignored.

  ## Returns

    * `{:ok, payload}` where `payload` is an EXCP `binary()`.
    * `{:error, %ExCodecs.Error{reason: :invalid_data,
      codec: :spatial_binary}}` when `data` is not a `%PointCloud{}`.

  ## Raises / exceptions

  A wrong top-level type is returned as `:invalid_data`. Because `opts` is
  ignored, even a non-keyword value does not raise. Manually malformed cloud or
  point structs can raise `FunctionClauseError`, `MatchError`, `ArgumentError`,
  or a bitstring construction exception when a point, tuple shape, channel
  range, or numeric field violates the struct contract.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> cloud = PointCloud.new([Point.new(1, 2, 3, color: {10, 20, 30})])
      iex> {:ok, <<"EXCP", 1::little-16, flags::little-16, 1::little-64, _::binary>>} =
      ...>   ExCodecs.Spatial.Codec.Binary.encode(cloud)
      iex> Bitwise.band(flags, 0b001)
      1
  """
  @spec encode(PointCloud.t(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(data, opts \\ [])

  def encode(%PointCloud{points: points}, _opts) do
    has_color? = Enum.any?(points, &Point.colored?/1)
    has_alpha? = Enum.any?(points, fn p -> match?({_, _, _, _}, p.color) end)
    has_normal? = Enum.any?(points, &Point.has_normal?/1)

    flags =
      0
      |> then(fn f -> if has_color?, do: Bitwise.bor(f, @flag_color), else: f end)
      |> then(fn f -> if has_alpha?, do: Bitwise.bor(f, @flag_alpha), else: f end)
      |> then(fn f -> if has_normal?, do: Bitwise.bor(f, @flag_normal), else: f end)

    header =
      <<@magic::binary, @version::little-unsigned-16, flags::little-unsigned-16,
        length(points)::little-unsigned-64>>

    body =
      IO.iodata_to_binary(
        Enum.map(points, fn p ->
          encode_point(p, flags)
        end)
      )

    {:ok, header <> body}
  end

  def encode(_, _) do
    {:error,
     Error.new(:invalid_data,
       codec: :spatial_binary,
       message: "Binary encode expects a PointCloud"
     )}
  end

  @doc """
  Decodes an EXCP version 1 payload into a point cloud.

  The decoder reads the global color/alpha/normal flags and the declared number
  of fixed-shape records described by `encode/2`. Trailing bytes are currently
  ignored. Decoded metadata contains `%{"format" => "excp", "version" => 1}`;
  attributes and other cloud-level fields use their constructor defaults.

  ## Arguments

    * `data` (`binary()`) — a complete EXCP payload.
    * `opts` (`keyword()`) — reserved and currently ignored.

  ## Returns

    * `{:ok, %PointCloud{}}`
    * `{:error, %ExCodecs.Error{reason: :invalid_data,
      codec: :spatial_binary}}` when the magic/header is invalid or too short,
      the version is not 1, or a declared coordinate, RGB/RGBA, or normal field
      is truncated.

  ## Raises / exceptions

  Corrupt/truncated payloads covered above are returned, and `opts` is ignored.
  This function has a catch-all data clause, so non-binary input also returns
  `:invalid_data`; it does not intentionally raise for external payloads.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.Codec.Binary.encode(PointCloud.new([Point.new(1.0, 2.0, 3.0)]))
      iex> {:ok, %PointCloud{points: [p]}} = ExCodecs.Spatial.Codec.Binary.decode(bin)
      iex> p.x
      1.0
  """
  @spec decode(binary(), keyword()) :: {:ok, PointCloud.t()} | {:error, Error.t()}
  def decode(data, opts \\ [])

  def decode(
        <<@magic::binary, version::little-unsigned-16, flags::little-unsigned-16,
          count::little-unsigned-64, rest::binary>>,
        _opts
      ) do
    if version != @version do
      {:error,
       Error.new(:invalid_data,
         codec: :spatial_binary,
         message: "Unsupported binary point format version #{version}"
       )}
    else
      with {:ok, points, _} <- decode_points(rest, count, flags) do
        meta = Metadata.new(entries: %{"format" => "excp", "version" => version})
        {:ok, PointCloud.new(points, metadata: meta)}
      end
    end
  end

  def decode(_, _) do
    {:error,
     Error.new(:invalid_data,
       codec: :spatial_binary,
       message: "Invalid ExCodecs binary point cloud"
     )}
  end

  @doc """
  Returns an enumerable over points in an EXCP payload.

  ## Arguments

    * `data` (`binary()`) — a complete EXCP payload.
    * `opts` (`keyword()`) — reserved and currently ignored.

  ## Returns

  An `Enumerable.t()` that yields decoded `%Point{}` values after the complete
  cloud has been materialized. If `decode/2` fails, it yields exactly one
  `{:error, %ExCodecs.Error{reason: :invalid_data,
  codec: :spatial_binary}}` element.

  ## Raises / exceptions

  Raises `FunctionClauseError` when `data` is not a binary because this public
  function is guarded. `opts` is ignored. Binary validation failures are
  delayed as the single error element rather than raised.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.Codec.Binary.encode(PointCloud.new([Point.new(0, 0, 0)]))
      iex> [%Point{x: 0.0, y: 0.0, z: 0.0}] =
      ...>   ExCodecs.Spatial.Codec.Binary.stream_decode(bin) |> Enum.to_list()
  """
  @spec stream_decode(binary(), keyword()) :: Enumerable.t()
  def stream_decode(data, opts \\ []) when is_binary(data) do
    case decode(data, opts) do
      {:ok, %PointCloud{points: points}} ->
        Stream.map(points, & &1)

      {:error, error} ->
        Stream.resource(
          fn -> {:error, error} end,
          fn
            {:error, e} -> {[{:error, e}], :done}
            :done -> {:halt, :done}
          end,
          fn _ -> :ok end
        )
    end
  end

  defp encode_point(%Point{} = p, flags) do
    xyz = <<p.x::little-float-32, p.y::little-float-32, p.z::little-float-32>>

    color =
      cond do
        Bitwise.band(flags, @flag_alpha) != 0 ->
          {r, g, b, a} = normalize_rgba(p.color)
          <<r::8, g::8, b::8, a::8>>

        Bitwise.band(flags, @flag_color) != 0 ->
          {r, g, b} = normalize_rgb(p.color)
          <<r::8, g::8, b::8>>

        true ->
          <<>>
      end

    normal =
      if Bitwise.band(flags, @flag_normal) != 0 do
        {nx, ny, nz} = p.normal || {0.0, 0.0, 0.0}
        <<nx::little-float-32, ny::little-float-32, nz::little-float-32>>
      else
        <<>>
      end

    xyz <> color <> normal
  end

  defp normalize_rgb(nil), do: {0, 0, 0}
  defp normalize_rgb({r, g, b}), do: {trunc(r), trunc(g), trunc(b)}
  defp normalize_rgb({r, g, b, _a}), do: {trunc(r), trunc(g), trunc(b)}

  defp normalize_rgba(nil), do: {0, 0, 0, 255}
  defp normalize_rgba({r, g, b}), do: {trunc(r), trunc(g), trunc(b), 255}
  defp normalize_rgba({r, g, b, a}), do: {trunc(r), trunc(g), trunc(b), trunc(a)}

  defp decode_points(bin, 0, _flags), do: {:ok, [], bin}

  defp decode_points(bin, count, flags) do
    Enum.reduce_while(1..count, {:ok, [], bin}, fn _, {:ok, acc, rest} ->
      case decode_point(rest, flags) do
        {:ok, point, next} -> {:cont, {:ok, [point | acc], next}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, points, rest} -> {:ok, Enum.reverse(points), rest}
      other -> other
    end
  end

  defp decode_point(
         <<x::little-float-32, y::little-float-32, z::little-float-32, rest::binary>>,
         flags
       ) do
    with {:ok, color, rest} <- take_color(rest, flags),
         {:ok, normal, rest} <- take_normal(rest, flags) do
      {:ok, Point.new(x, y, z, color: color, normal: normal), rest}
    end
  end

  defp decode_point(_, _),
    do:
      {:error, Error.new(:invalid_data, codec: :spatial_binary, message: "Truncated point record")}

  defp take_color(bin, flags) when Bitwise.band(flags, @flag_alpha) != 0 do
    case bin do
      <<r::8, g::8, b::8, a::8, rest::binary>> -> {:ok, {r, g, b, a}, rest}
      _ -> {:error, Error.new(:invalid_data, codec: :spatial_binary, message: "Truncated RGBA")}
    end
  end

  defp take_color(bin, flags) when Bitwise.band(flags, @flag_color) != 0 do
    case bin do
      <<r::8, g::8, b::8, rest::binary>> -> {:ok, {r, g, b}, rest}
      _ -> {:error, Error.new(:invalid_data, codec: :spatial_binary, message: "Truncated RGB")}
    end
  end

  defp take_color(bin, _), do: {:ok, nil, bin}

  defp take_normal(bin, flags) when Bitwise.band(flags, @flag_normal) != 0 do
    case bin do
      <<nx::little-float-32, ny::little-float-32, nz::little-float-32, rest::binary>> ->
        {:ok, {nx, ny, nz}, rest}

      _ ->
        {:error, Error.new(:invalid_data, codec: :spatial_binary, message: "Truncated normal")}
    end
  end

  defp take_normal(bin, _), do: {:ok, nil, bin}
end
