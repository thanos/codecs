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
  alias ExCodecs.Spatial.{Metadata, Point, PointCloud}

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
  Streams `%Point{}` values to an EXCP file using an explicit schema.

  Writes a placeholder header, encodes each point as it arrives, then seeks
  back to patch the final count. Peak memory is O(one point), not the cloud.

  ## Arguments

    * `enumerable` (`Enumerable.t()`) — `%Point{}` elements.
    * `path` (`Path.t()`) — destination file path.
    * `opts` (`keyword()`) — requires `:schema`, a list such as `[]`,
      `[:color]`, `[:color, :alpha]`, `[:normal]`, or `[:color, :normal]`.
      Map form `%{color: true, alpha: false, normal: true}` is also accepted.
      `:alpha` implies color bytes (RGBA).

  ## Returns

    * `:ok`
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` when `:schema` is
      missing or invalid
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when an element is not
      a `%Point{}`
    * `{:error, %ExCodecs.Error{reason: :io_error}}` on file failures

  ## Raises / exceptions

  Schema and non-`%Point{}` element failures are returned. Invalid path terms or
  non-keyword `opts` can raise `FunctionClauseError` or `ArgumentError` in the
  path/file/keyword APIs. Malformed point field shapes can raise during
  bitstring construction (same class of exceptions as `encode/2`).

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, Codec.Binary}
      iex> path = Path.join(System.tmp_dir!(), "excp_enc_#{System.unique_integer([:positive])}.excp")
      iex> :ok = Binary.stream_encode_to_file([Point.new(1, 2, 3, color: {1, 2, 3})], path, schema: [:color])
      iex> {:ok, <<"EXCP", _::binary>>} = File.read(path)
      iex> File.rm!(path)
      :ok
  """
  @spec stream_encode_to_file(Enumerable.t(), Path.t(), keyword()) :: :ok | {:error, Error.t()}
  def stream_encode_to_file(enumerable, path, opts \\ []) do
    with {:ok, flags} <- fetch_schema_flags(opts),
         {:ok, io} <- open_write(path) do
      try do
        :ok = IO.binwrite(io, excp_header(flags, 0))

        count =
          Enum.reduce(enumerable, 0, fn
            %Point{} = point, n ->
              :ok = IO.binwrite(io, encode_point(point, flags))
              n + 1

            other, _n ->
              throw({:bad_point, other})
          end)

        {:ok, 0} = :file.position(io, 0)
        :ok = IO.binwrite(io, excp_header(flags, count))
        :ok
      catch
        {:bad_point, other} ->
          {:error,
           Error.new(:invalid_data,
             codec: :spatial_binary,
             message: "EXCP stream encode expects Point structs, got: #{inspect(other)}"
           )}
      after
        File.close(io)
      end
    end
  end

  defp fetch_schema_flags(opts) do
    case Keyword.fetch(opts, :schema) do
      :error ->
        {:error,
         Error.new(:invalid_options,
           codec: :spatial_binary,
           message: "EXCP stream_encode_to_file requires schema: (e.g. schema: [:color])"
         )}

      {:ok, schema} ->
        schema_to_flags(schema)
    end
  end

  defp schema_to_flags(schema) when is_list(schema) do
    alpha? = schema_flag?(schema, :alpha)
    color? = alpha? or schema_flag?(schema, :color)
    normal? = schema_flag?(schema, :normal)

    unknown = Enum.reject(schema, &known_excp_schema_entry?/1)

    if unknown != [] do
      {:error,
       Error.new(:invalid_options,
         codec: :spatial_binary,
         message: "Unknown EXCP schema entries: #{inspect(unknown)}"
       )}
    else
      {:ok, flags_from_schema(color?, alpha?, normal?)}
    end
  end

  defp schema_to_flags(schema) when is_map(schema) do
    schema_to_flags(Map.to_list(schema))
  end

  defp schema_to_flags(other) do
    {:error,
     Error.new(:invalid_options,
       codec: :spatial_binary,
       message: "EXCP schema must be a list or map, got: #{inspect(other)}"
     )}
  end

  defp known_excp_schema_entry?(entry) when entry in [:color, :alpha, :normal], do: true
  defp known_excp_schema_entry?({key, _}) when key in [:color, :alpha, :normal], do: true
  defp known_excp_schema_entry?(_), do: false

  defp flags_from_schema(color?, alpha?, normal?) do
    0
    |> maybe_flag(color?, @flag_color)
    |> maybe_flag(alpha?, @flag_alpha)
    |> maybe_flag(normal?, @flag_normal)
  end

  defp maybe_flag(flags, true, bit), do: Bitwise.bor(flags, bit)
  defp maybe_flag(flags, false, _bit), do: flags

  defp schema_flag?(schema, key) when is_list(schema) do
    key in schema or Keyword.get(schema, key, false) == true
  end

  defp excp_header(flags, count) do
    <<@magic::binary, @version::little-unsigned-16, flags::little-unsigned-16,
      count::little-unsigned-64>>
  end

  defp open_write(path) do
    case File.open(path, [:write, :binary, :raw, :read]) do
      {:ok, io} -> {:ok, io}
      {:error, reason} -> io_error(reason)
    end
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
  Returns an enumerable over points in an EXCP payload or file.

  ## Streaming behavior

    * `source: :file` (or `:auto` when the argument looks like a path to a
      regular file) reads the 16-byte header, then **one record at a time**
      via `IO.binread/2`. Peak memory is O(header + one record), not the
      whole cloud.
    * `source: :binary` (or `:auto` for an in-memory EXCP payload) still
      materializes through `decode/2`, then yields the list. A future Rust
      backend may memory-map large binaries instead.

  Prefer `source: :file` for multi‑MB / multi‑GB `.excp` paths.

  ## Arguments

    * `source` (`Path.t() | binary()`) — filesystem path or complete EXCP
      payload. Both are binaries, so `:source` controls resolution.
    * `opts` (`keyword()`) — `:source` may be `:auto` (default), `:file`, or
      `:binary`.

  ## Returns

  An `Enumerable.t()` yielding `%Point{}` values. Failures are delayed until
  enumeration as exactly one `{:error, %ExCodecs.Error{}}`:

    * `reason: :io_error` — the file cannot be opened or read
    * `reason: :invalid_data` — bad magic/version, truncated header, or a
      truncated record mid-stream (`codec: :spatial_binary`)

  ## Raises / exceptions

  Raises `FunctionClauseError` when `source` is not a binary. Unsupported
  `:source` values raise `CaseClauseError`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.Codec.Binary.encode(PointCloud.new([Point.new(0, 0, 0)]))
      iex> [%Point{x: 0.0, y: 0.0, z: 0.0}] =
      ...>   ExCodecs.Spatial.Codec.Binary.stream_decode(bin) |> Enum.to_list()
  """
  @spec stream_decode(Path.t() | binary(), keyword()) :: Enumerable.t()
  def stream_decode(source, opts \\ [])

  def stream_decode(data, opts) when is_binary(data) do
    case resolve_source(data, opts) do
      {:ok, :binary, bin} ->
        stream_from_binary(bin, opts)

      {:ok, :file, path} ->
        Stream.resource(
          fn -> open_excp_file(path) end,
          &next_excp_item/1,
          &close_excp_file/1
        )
    end
  end

  defp stream_from_binary(bin, opts) do
    case decode(bin, opts) do
      {:ok, %PointCloud{points: points}} ->
        Stream.map(points, & &1)

      {:error, error} ->
        error_stream(error)
    end
  end

  defp resolve_source(bin, opts) do
    case Keyword.get(opts, :source, :auto) do
      :binary ->
        {:ok, :binary, bin}

      :file ->
        {:ok, :file, bin}

      :auto ->
        if path_like?(bin) and File.regular?(bin) do
          {:ok, :file, bin}
        else
          {:ok, :binary, bin}
        end
    end
  end

  defp path_like?(bin) do
    byte_size(bin) < 4096 and not String.starts_with?(bin, @magic) and
      (String.contains?(bin, "/") or String.contains?(bin, "\\") or
         String.ends_with?(bin, [".excp", ".bin"]))
  end

  defp open_excp_file(path) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} -> parse_excp_header(io, IO.binread(io, 16))
      {:error, reason} -> io_error(reason)
    end
  end

  defp parse_excp_header(
         io,
         <<@magic::binary, version::little-unsigned-16, flags::little-unsigned-16,
           count::little-unsigned-64>>
       ) do
    if version != @version do
      File.close(io)

      {:error,
       Error.new(:invalid_data,
         codec: :spatial_binary,
         message: "Unsupported binary point format version #{version}"
       )}
    else
      {:ok, io, flags, count, record_stride(flags), 0}
    end
  end

  defp parse_excp_header(io, :eof) do
    File.close(io)

    {:error,
     Error.new(:invalid_data,
       codec: :spatial_binary,
       message: "Invalid ExCodecs binary point cloud"
     )}
  end

  defp parse_excp_header(io, data) when is_binary(data) do
    File.close(io)

    {:error,
     Error.new(:invalid_data,
       codec: :spatial_binary,
       message: "Invalid ExCodecs binary point cloud"
     )}
  end

  defp parse_excp_header(io, {:error, reason}) do
    File.close(io)
    io_error(reason)
  end

  defp next_excp_item({:ok, io, _flags, count, _stride, i}) when i >= count do
    {:halt, {:done, io}}
  end

  defp next_excp_item({:ok, io, flags, count, stride, i}) do
    case IO.binread(io, stride) do
      data when is_binary(data) and byte_size(data) == stride ->
        case decode_point(data, flags) do
          {:ok, point, _} ->
            {[point], {:ok, io, flags, count, stride, i + 1}}

          {:error, error} ->
            {[{:error, error}], {:done, io}}
        end

      :eof ->
        {[
           {:error,
            Error.new(:invalid_data,
              codec: :spatial_binary,
              message: "Truncated point record"
            )}
         ], {:done, io}}

      data when is_binary(data) ->
        {[
           {:error,
            Error.new(:invalid_data,
              codec: :spatial_binary,
              message: "Truncated point record"
            )}
         ], {:done, io}}

      {:error, reason} ->
        {[{:error, io_error_struct(reason)}], {:done, io}}
    end
  end

  defp next_excp_item({:error, error}), do: {[{:error, error}], :done}
  defp next_excp_item({:done, _io}), do: {:halt, :done}
  defp next_excp_item(:done), do: {:halt, :done}

  defp close_excp_file({:ok, io, _, _, _, _}), do: File.close(io)
  defp close_excp_file({:done, io}), do: File.close(io)
  defp close_excp_file(_), do: :ok

  defp record_stride(flags) do
    color =
      cond do
        Bitwise.band(flags, @flag_alpha) != 0 -> 4
        Bitwise.band(flags, @flag_color) != 0 -> 3
        true -> 0
      end

    normal = if Bitwise.band(flags, @flag_normal) != 0, do: 12, else: 0
    12 + color + normal
  end

  defp io_error(reason) do
    {:error, io_error_struct(reason)}
  end

  defp io_error_struct(reason) do
    Error.new(:io_error,
      codec: :spatial_binary,
      message: "Failed to read EXCP file: #{inspect(reason)}",
      details: reason
    )
  end

  defp error_stream(error) do
    Stream.resource(
      fn -> {:error, error} end,
      fn
        {:error, e} -> {[{:error, e}], :done}
        :done -> {:halt, :done}
      end,
      fn _ -> :ok end
    )
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

  defp normalize_rgb(color) do
    case color do
      nil -> {0, 0, 0}
      {r, g, b} -> {trunc(r), trunc(g), trunc(b)}
      {r, g, b, _a} -> {trunc(r), trunc(g), trunc(b)}
    end
  end

  defp normalize_rgba(color) do
    case color do
      nil -> {0, 0, 0, 255}
      {r, g, b} -> {trunc(r), trunc(g), trunc(b), 255}
      {r, g, b, a} -> {trunc(r), trunc(g), trunc(b), trunc(a)}
    end
  end

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
