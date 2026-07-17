defmodule ExCodecs.Spatial.Codec.PLY do
  @moduledoc """
  ASCII and binary PLY for point clouds and Gaussian splats.

  ## Options

    * `:format` / `:ply_format` — wire encoding: `:ascii` (default),
      `:binary` / `:binary_le`, `:binary_be` (not Spatial's `format: :ply`)
    * `:comments` — header comments
    * `:as` — decode as `:auto` | `:point_cloud` | `:gaussian_cloud`
    * `:source` — for `stream_decode/2`: `:auto` | `:file` | `:binary`

  Public functions: `encode/2`, `decode/2`, `stream_decode/2`.
  """

  alias ExCodecs.Error
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Metadata, Point, PointCloud}

  @typedoc """
  Wire encoding used for a PLY payload.

  `:ascii` writes textual scalar values. `:binary_le` and `:binary_be` write
  packed scalar values in little- and big-endian order, respectively.
  `:binary` is an encoding-option shorthand for `:binary_le`; decoded headers
  report the explicit endian atom.

  For example, `encode(cloud, ply_format: :binary_be)` emits a
  `format binary_big_endian 1.0` header.
  """
  @type ply_format :: :ascii | :binary | :binary_le | :binary_be

  @doc """
  Encodes a point cloud or Gaussian cloud as a PLY 1.0 payload.

  Point vertices always contain `x`, `y`, and `z` as `float`. If any point has
  color or a normal, the corresponding `uchar` RGB/RGBA or `float` normal
  properties are emitted for every point; missing values are zero-filled
  (alpha defaults to 255). The union of point attribute keys is emitted as
  sorted `float` properties, with absent attributes set to `0.0`.

  Gaussian vertices contain position, `f_dc_0..2`, opacity, scale, and
  quaternion `rot_0..3` (`w, x, y, z`) as `float`. If spherical-harmonic
  coefficients are present, flattened `f_rest_N` properties are appended and
  shorter rows are zero-filled.

  ## Arguments

    * `data` (`PointCloud.t() | GaussianCloud.t()`) — a cloud containing valid
      `%Point{}` or `%Gaussian{}` structs.
    * `opts` (`keyword()`) — supported options:
      * `:ply_format` — preferred wire format: `:ascii` (default), `:binary`
        (little-endian), `:binary_le`, or `:binary_be`.
      * `:format` — legacy alias for `:ply_format` when calling this codec
        directly. `:ply_format` takes precedence.
      * `:comments` — enumerable of strings for PLY `comment` header lines;
        defaults to `cloud.metadata.comments`.

  `:little` and `:big` are also normalized to little-/big-endian output.
  Any unrecognized wire-format value currently falls back to `:ascii`.

  ## Returns

    * `{:ok, payload}` where `payload` is an ASCII or binary PLY `binary()`.
    * `{:error, %ExCodecs.Error{reason: :invalid_data, codec: :ply}}` when
      `data` is not a supported cloud or any exception occurs while deriving
      properties, building the header, or encoding rows.

  ## Raises / exceptions

  The cloud clauses rescue encoding exceptions and return `:invalid_data`,
  including invalid keyword options, malformed nested structs, non-string
  comments, invalid scalar ranges/types, and bad attribute shapes. Unsupported
  top-level data is also returned as `:invalid_data`; this function does not
  intentionally raise.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> cloud = PointCloud.new([Point.new(0, 1, 2, color: {255, 64, 0})])
      iex> {:ok, ply} = ExCodecs.Spatial.Codec.PLY.encode(cloud, ply_format: :ascii)
      iex> String.contains?(ply, "property uchar red")
      true
  """
  @spec encode(PointCloud.t() | GaussianCloud.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t()}
  def encode(data, opts \\ [])

  def encode(%PointCloud{} = cloud, opts) do
    format = normalize_format(ply_format_opt(opts))
    comments = Keyword.get(opts, :comments, cloud.metadata.comments)

    with {:ok, props} <- point_properties(cloud.points) do
      body = encode_points(cloud.points, props, format)
      header = build_header(format, length(cloud.points), props, comments)
      {:ok, header <> body}
    end
  rescue
    e ->
      {:error,
       Error.new(:invalid_data,
         codec: :ply,
         message: "PLY encode failed: #{Exception.message(e)}"
       )}
  end

  def encode(%GaussianCloud{} = cloud, opts) do
    format = normalize_format(ply_format_opt(opts))
    comments = Keyword.get(opts, :comments, cloud.metadata.comments)
    props = gaussian_properties(cloud.gaussians)
    body = encode_gaussians(cloud.gaussians, props, format)
    header = build_header(format, length(cloud.gaussians), props, comments)
    {:ok, header <> body}
  rescue
    e ->
      {:error,
       Error.new(:invalid_data,
         codec: :ply,
         message: "PLY encode failed: #{Exception.message(e)}"
       )}
  end

  def encode(_data, _opts) do
    {:error,
     Error.new(:invalid_data,
       codec: :ply,
       message: "PLY encode expects a PointCloud or GaussianCloud"
     )}
  end

  @doc """
  Decodes a complete PLY 1.0 payload into a point or Gaussian cloud.

  ASCII and binary little-/big-endian scalar vertex properties are supported:
  `char`/`int8`, `uchar`/`uint8`, `short`/`int16`, `ushort`/`uint16`,
  `int`/`int32`, `uint`/`uint32`, `float`/`float32`, and
  `double`/`float64`. List properties and non-vertex payloads are unsupported.

  Point decoding recognizes `x/y/z`, RGB or RGBA, and `nx/ny/nz`; all other
  scalar properties become string-keyed point attributes. Gaussian decoding
  interprets `f_dc_*`, opacity, scale, rotation, and ordered `f_rest_*`
  properties. Header comments and the detected PLY format are retained in
  cloud metadata.

  ## Arguments

    * `data` (`binary()`) — the complete PLY header and vertex body.
    * `opts` (`keyword()`) — `:as` may be `:auto` (default), `:point_cloud`, or
      `:gaussian_cloud`. `:auto` chooses Gaussian output when the property set
      contains `f_dc_0`, `scale_0`, or `rot_0`; otherwise it chooses points.
      The wire format is always read from the header.

  ## Returns

    * `{:ok, %PointCloud{}}` or `{:ok, %GaussianCloud{}}`, including metadata.
    * `{:error, %ExCodecs.Error{reason: :invalid_data, codec: :ply}}` for
      non-binary input, missing/invalid magic or format/header lines, missing
      vertex elements, invalid counts/properties, unsupported list/property
      types, too few ASCII rows, or a short binary body.

  ## Raises / exceptions

  The listed structural failures are returned. `Keyword.get/3` raises
  `FunctionClauseError` when `opts` is not a proper keyword list. An unsupported
  `:as` value raises `CaseClauseError`. Malformed row contents may also raise
  (`KeyError`, `ArgumentError`, `FunctionClauseError`, or a bitstring match
  exception), because scalar/required-property validation is not fully wrapped;
  invalid ASCII scalar tokens are currently coerced to `0.0`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> cloud = PointCloud.new([Point.new(1.0, 0.0, 0.0, normal: {0.0, 0.0, 1.0})])
      iex> {:ok, ply} = ExCodecs.Spatial.Codec.PLY.encode(cloud, ply_format: :binary_le)
      iex> {:ok, %PointCloud{points: [point]}} = ExCodecs.Spatial.Codec.PLY.decode(ply)
      iex> point.normal
      {0.0, 0.0, 1.0}
  """
  @spec decode(binary(), keyword()) ::
          {:ok, PointCloud.t() | GaussianCloud.t()} | {:error, Error.t()}
  def decode(data, opts \\ [])

  def decode(data, opts) when is_binary(data) do
    as = Keyword.get(opts, :as, :auto)

    with {:ok, header, body} <- split_header(data),
         {:ok, parsed} <- parse_header(header) do
      decode_parsed_body(resolve_as(as, parsed.properties), body, parsed)
    end
  end

  def decode(_data, _opts) do
    {:error, Error.new(:invalid_data, codec: :ply, message: "PLY data must be a binary")}
  end

  @doc """
  Returns an enumerable over vertices from a PLY path or binary.

  ## Streaming behavior

    * `source: :file` (or `:auto` path detection): scans the header until
      `end_header`, then yields one vertex at a time — binary formats via
      fixed-stride `IO.binread/2`, ASCII via line reads. Peak memory is
      O(header + one vertex / read chunk), not the whole cloud.
    * `source: :binary`: still materializes through `decode/2`, then yields.

  ## Arguments

    * `source` (`Path.t() | binary()`) — a path or complete PLY payload.
    * `opts` (`keyword()`) — `:source` may be `:auto` (default), `:file`, or
      `:binary`. Auto mode treats a short path-like binary as a file only when
      it names a regular file; otherwise it is payload data. `:as` has the same
      meaning as in `decode/2`.

  ## Returns

  An `Enumerable.t()` yielding `%Point{}` or `%Gaussian{}`. Decode failures,
  including `reason: :invalid_data`, are represented by exactly one
  `{:error, %ExCodecs.Error{}}` element. A selected path that cannot be read
  yields one error with `reason: :io_error` and the file reason in `details`.

  ## Raises / exceptions

  File and normal decode failures become stream elements. A non-binary
  `source` raises `FunctionClauseError`. Keyword access raises
  `FunctionClauseError` for invalid `opts`; unsupported `:source` values raise
  `CaseClauseError`. Exceptions described by `decode/2` may occur while the
  stream is initialized or enumerated.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> {:ok, ply} = ExCodecs.Spatial.Codec.PLY.encode(PointCloud.new([Point.new(0, 0, 0)]))
      iex> [%Point{x: 0.0}] = ExCodecs.Spatial.Codec.PLY.stream_decode(ply) |> Enum.to_list()
  """
  @spec stream_decode(binary() | Path.t(), keyword()) :: Enumerable.t()
  def stream_decode(source, opts \\ [])

  def stream_decode(data, opts) when is_binary(data) do
    case resolve_ply_source(data, opts) do
      {:ok, :binary, bin} ->
        stream_from_decoded_binary(bin, opts)

      {:ok, :file, path} ->
        Stream.resource(
          fn -> open_ply_stream(path, opts) end,
          &next_ply_stream_item/1,
          &close_ply_stream/1
        )
    end
  end

  defp stream_from_decoded_binary(bin, opts) do
    case decode_to_list(bin, opts) do
      {:ok, items} ->
        Stream.map(items, & &1)

      {:error, error} ->
        Stream.resource(fn -> {:error, error} end, &error_stream/1, fn _ -> :ok end)
    end
  end

  defp resolve_ply_source(bin, opts) do
    case Keyword.get(opts, :source, :auto) do
      :binary ->
        {:ok, :binary, bin}

      :file ->
        {:ok, :file, bin}

      :auto ->
        if path_like_ply?(bin) and File.regular?(bin) do
          {:ok, :file, bin}
        else
          {:ok, :binary, bin}
        end
    end
  end

  defp path_like_ply?(bin) do
    byte_size(bin) < 4096 and not ply_binary?(bin) and
      (String.contains?(bin, "/") or String.contains?(bin, "\\") or
         String.ends_with?(bin, [".ply", ".PLY"]))
  end

  @doc false
  def decode_header_and_body(data) when is_binary(data) do
    with {:ok, header, body} <- split_header(data),
         {:ok, parsed} <- parse_header(header) do
      {:ok, parsed, body}
    end
  end

  # --- Header ---------------------------------------------------------------

  defp ply_binary?(<<data::binary>>) do
    String.starts_with?(data, "ply")
  end

  defp split_header(data) do
    case :binary.match(data, "end_header") do
      {pos, len} ->
        # skip end_header and following newline(s)
        rest = binary_part(data, pos + len, byte_size(data) - pos - len)
        body = strip_leading_newlines(rest)
        header = binary_part(data, 0, pos + len)
        {:ok, header, body}

      :nomatch ->
        {:error, Error.new(:invalid_data, codec: :ply, message: "PLY header missing end_header")}
    end
  end

  defp strip_leading_newlines(<<"\r\n", rest::binary>>), do: rest
  defp strip_leading_newlines(<<"\n", rest::binary>>), do: rest
  defp strip_leading_newlines(<<"\r", rest::binary>>), do: rest
  defp strip_leading_newlines(bin), do: bin

  defp parse_header(header) do
    lines =
      header
      |> String.split(~r/\r\n|\n|\r/, trim: true)
      |> Enum.map(&String.trim/1)

    with :ok <- validate_magic(lines),
         {:ok, format} <- find_format(lines),
         {:ok, count, properties} <- find_vertex_element(lines) do
      comments =
        lines
        |> Enum.filter(&String.starts_with?(&1, "comment "))
        |> Enum.map(&String.trim_leading(&1, "comment "))

      {:ok,
       %{
         format: format,
         count: count,
         properties: properties,
         comments: comments
       }}
    end
  end

  defp validate_magic(["ply" | _]), do: :ok

  defp validate_magic(_) do
    {:error, Error.new(:invalid_data, codec: :ply, message: "PLY data must start with 'ply'")}
  end

  defp find_format(lines) do
    case Enum.find(lines, &String.starts_with?(&1, "format ")) do
      "format ascii 1.0" <> _ ->
        {:ok, :ascii}

      "format binary_little_endian 1.0" <> _ ->
        {:ok, :binary_le}

      "format binary_big_endian 1.0" <> _ ->
        {:ok, :binary_be}

      other when is_binary(other) ->
        {:error, Error.new(:invalid_data, codec: :ply, message: "Unsupported PLY format: #{other}")}

      nil ->
        {:error, Error.new(:invalid_data, codec: :ply, message: "PLY format line missing")}
    end
  end

  defp find_vertex_element(lines) do
    case Enum.find_index(lines, &String.starts_with?(&1, "element vertex ")) do
      nil ->
        {:error, Error.new(:invalid_data, codec: :ply, message: "No vertex element in PLY")}

      idx ->
        parse_vertex_element(lines, idx)
    end
  end

  defp parse_vertex_element(lines, idx) do
    with {:ok, count} <- parse_vertex_count(Enum.at(lines, idx)),
         {:ok, props} <- parse_vertex_properties(lines, idx) do
      {:ok, count, props}
    end
  end

  defp parse_vertex_properties(lines, idx) do
    props =
      lines
      |> Enum.drop(idx + 1)
      |> Enum.take_while(&String.starts_with?(&1, "property "))
      |> Enum.map(&parse_property/1)

    if Enum.any?(props, &match?({:error, _}, &1)) do
      {:error, Error.new(:invalid_data, codec: :ply, message: "Invalid PLY property")}
    else
      {:ok, props}
    end
  end

  defp parse_vertex_count(line) do
    case String.split(line) do
      ["element", "vertex", count_str] ->
        case Integer.parse(count_str) do
          {count, ""} when count >= 0 ->
            {:ok, count}

          _ ->
            {:error,
             Error.new(:invalid_data, codec: :ply, message: "Invalid vertex count in PLY header")}
        end

      _ ->
        {:error,
         Error.new(:invalid_data, codec: :ply, message: "Malformed element vertex line in PLY")}
    end
  end

  defp parse_property("property list " <> _),
    do: {:error, :list_properties_unsupported}

  defp parse_property("property " <> rest) do
    case String.split(rest) do
      [type, name] ->
        case property_type(type) do
          {:ok, t} -> %{type: t, name: name}
          :error -> {:error, :unknown_property_type}
        end

      _ ->
        {:error, :bad_property}
    end
  end

  defp property_type("char"), do: {:ok, :char}
  defp property_type("uchar"), do: {:ok, :uchar}
  defp property_type("short"), do: {:ok, :short}
  defp property_type("ushort"), do: {:ok, :ushort}
  defp property_type("int"), do: {:ok, :int}
  defp property_type("uint"), do: {:ok, :uint}
  defp property_type("float"), do: {:ok, :float}
  defp property_type("double"), do: {:ok, :double}
  defp property_type("int8"), do: {:ok, :char}
  defp property_type("uint8"), do: {:ok, :uchar}
  defp property_type("int16"), do: {:ok, :short}
  defp property_type("uint16"), do: {:ok, :ushort}
  defp property_type("int32"), do: {:ok, :int}
  defp property_type("uint32"), do: {:ok, :uint}
  defp property_type("float32"), do: {:ok, :float}
  defp property_type("float64"), do: {:ok, :double}
  defp property_type(_), do: :error

  # --- Encode points --------------------------------------------------------

  defp point_properties(points) do
    has_color? = Enum.any?(points, &Point.colored?/1)
    has_alpha? = Enum.any?(points, fn p -> match?({_, _, _, _}, p.color) end)
    has_normal? = Enum.any?(points, &Point.has_normal?/1)

    attr_names =
      points
      |> Enum.flat_map(fn p -> Map.keys(p.attributes) end)
      |> Enum.uniq()
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    base = [
      %{type: :float, name: "x"},
      %{type: :float, name: "y"},
      %{type: :float, name: "z"}
    ]

    color =
      cond do
        has_alpha? ->
          [
            %{type: :uchar, name: "red"},
            %{type: :uchar, name: "green"},
            %{type: :uchar, name: "blue"},
            %{type: :uchar, name: "alpha"}
          ]

        has_color? ->
          [
            %{type: :uchar, name: "red"},
            %{type: :uchar, name: "green"},
            %{type: :uchar, name: "blue"}
          ]

        true ->
          []
      end

    normal =
      if has_normal? do
        [
          %{type: :float, name: "nx"},
          %{type: :float, name: "ny"},
          %{type: :float, name: "nz"}
        ]
      else
        []
      end

    attrs = Enum.map(attr_names, fn name -> %{type: :float, name: name} end)
    {:ok, base ++ color ++ normal ++ attrs}
  end

  defp gaussian_properties(gaussians) do
    has_sh? = Enum.any?(gaussians, &(&1.sh != nil))

    base = [
      %{type: :float, name: "x"},
      %{type: :float, name: "y"},
      %{type: :float, name: "z"},
      %{type: :float, name: "f_dc_0"},
      %{type: :float, name: "f_dc_1"},
      %{type: :float, name: "f_dc_2"},
      %{type: :float, name: "opacity"},
      %{type: :float, name: "scale_0"},
      %{type: :float, name: "scale_1"},
      %{type: :float, name: "scale_2"},
      %{type: :float, name: "rot_0"},
      %{type: :float, name: "rot_1"},
      %{type: :float, name: "rot_2"},
      %{type: :float, name: "rot_3"}
    ]

    base ++ sh_property_defs(gaussians, has_sh?)
  end

  defp sh_property_defs(_gaussians, false), do: []

  defp sh_property_defs(gaussians, true) do
    max_rest =
      gaussians
      |> Enum.map(&sh_rest_coeff_count/1)
      |> Enum.max()

    for i <- 0..(max_rest - 1)//1, max_rest > 0 do
      %{type: :float, name: "f_rest_#{i}"}
    end
  end

  defp sh_rest_coeff_count(%{sh: nil}), do: 0
  defp sh_rest_coeff_count(%{sh: [_dc | rest]}), do: length(List.flatten(rest))
  defp sh_rest_coeff_count(_), do: 0

  defp build_header(format, count, props, comments) do
    format_line =
      case format do
        :ascii -> "format ascii 1.0"
        :binary_le -> "format binary_little_endian 1.0"
        :binary_be -> "format binary_big_endian 1.0"
      end

    comment_lines = Enum.map(comments, fn c -> "comment #{c}" end)

    prop_lines =
      Enum.map(props, fn %{type: type, name: name} ->
        "property #{type_name(type)} #{name}"
      end)

    Enum.join(
      ["ply", format_line] ++
        comment_lines ++
        ["element vertex #{count}"] ++
        prop_lines ++
        ["end_header", ""],
      "\n"
    )
  end

  # Encode only ever emits float and uchar properties (attributes are promoted
  # to float32; see docs/spatial_formats.md), so no other types are needed here.
  defp type_name(:uchar), do: "uchar"
  defp type_name(:float), do: "float"

  defp encode_points(points, props, :ascii) do
    points
    |> Enum.map_join("\n", fn point ->
      point
      |> point_values(props)
      |> Enum.map_join(" ", &ascii_value/1)
    end)
    |> then(&(&1 <> "\n"))
  end

  defp encode_points(points, props, endian) when endian in [:binary_le, :binary_be] do
    IO.iodata_to_binary(
      Enum.map(points, fn point ->
        point
        |> point_values(props)
        |> Enum.zip(props)
        |> Enum.map(fn {value, %{type: type}} -> pack(type, value, endian) end)
      end)
    )
  end

  defp point_values(%Point{} = p, props) do
    {nx, ny, nz} = p.normal || {0.0, 0.0, 0.0}

    known = %{
      "x" => p.x,
      "y" => p.y,
      "z" => p.z,
      "nx" => nx,
      "ny" => ny,
      "nz" => nz,
      "red" => color_channel(p.color, 0),
      "green" => color_channel(p.color, 1),
      "blue" => color_channel(p.color, 2),
      "alpha" => color_channel(p.color, 3, 255)
    }

    Enum.map(props, fn %{name: name} -> attribute_value(known, p.attributes, name) end)
  end

  defp attribute_value(known, attributes, name) do
    cond do
      Map.has_key?(known, name) -> Map.fetch!(known, name)
      Map.has_key?(attributes, name) -> Map.fetch!(attributes, name)
      true -> 0.0
    end
  end

  defp color_channel(color, idx, default \\ 0)
  defp color_channel(nil, _idx, default), do: default

  defp color_channel(color, idx, default) do
    if idx < tuple_size(color), do: elem(color, idx), else: default
  end

  defp encode_gaussians(gaussians, props, :ascii) do
    gaussians
    |> Enum.map_join("\n", fn g ->
      g
      |> gaussian_values(props)
      |> Enum.map_join(" ", &ascii_value/1)
    end)
    |> then(&(&1 <> "\n"))
  end

  defp encode_gaussians(gaussians, props, endian) when endian in [:binary_le, :binary_be] do
    IO.iodata_to_binary(
      Enum.map(gaussians, fn g ->
        g
        |> gaussian_values(props)
        |> Enum.zip(props)
        |> Enum.map(fn {value, %{type: type}} -> pack(type, value, endian) end)
      end)
    )
  end

  defp gaussian_values(%Gaussian{} = g, props) do
    {x, y, z} = g.position
    {r, gc, b} = g.color
    {sx, sy, sz} = g.scale
    {rw, rx, ry, rz} = g.rotation
    rest = sh_rest_flat(g.sh)

    known = %{
      "x" => x,
      "y" => y,
      "z" => z,
      "f_dc_0" => r,
      "f_dc_1" => gc,
      "f_dc_2" => b,
      "opacity" => g.opacity,
      "scale_0" => sx,
      "scale_1" => sy,
      "scale_2" => sz,
      "rot_0" => rw,
      "rot_1" => rx,
      "rot_2" => ry,
      "rot_3" => rz
    }

    Enum.map(props, fn %{name: name} ->
      case Map.fetch(known, name) do
        {:ok, value} -> value
        :error -> rest_coeff(name, rest)
      end
    end)
  end

  defp rest_coeff("f_rest_" <> idx, rest), do: Enum.at(rest, String.to_integer(idx), 0.0)

  defp sh_rest_flat(nil), do: []
  defp sh_rest_flat([_dc | rest]), do: List.flatten(rest)
  defp sh_rest_flat(other) when is_list(other), do: List.flatten(other)

  defp ascii_value(v) when is_integer(v), do: Integer.to_string(v)
  defp ascii_value(v) when is_float(v), do: :erlang.float_to_binary(v, [:short])

  # Like type_name/1, encode only packs float and uchar values; decode's
  # unpack/3 still handles the full range of PLY scalar property types.
  defp pack(:uchar, v, _), do: <<trunc(v)::unsigned-integer-8>>
  defp pack(:float, v, :binary_le), do: <<v * 1.0::little-float-32>>
  defp pack(:float, v, :binary_be), do: <<v * 1.0::big-float-32>>

  # --- Decode ---------------------------------------------------------------

  defp resolve_as(:point_cloud, _), do: :point_cloud
  defp resolve_as(:gaussian_cloud, _), do: :gaussian_cloud

  defp resolve_as(:auto, props) do
    names = MapSet.new(Enum.map(props, & &1.name))

    if MapSet.member?(names, "f_dc_0") or MapSet.member?(names, "scale_0") or
         MapSet.member?(names, "rot_0") do
      :gaussian_cloud
    else
      :point_cloud
    end
  end

  defp decode_parsed_body(:point_cloud, body, parsed) do
    with {:ok, points} <- decode_vertices(body, parsed) do
      {:ok, PointCloud.new(points, metadata: ply_metadata(parsed))}
    end
  end

  defp decode_parsed_body(:gaussian_cloud, body, parsed) do
    with {:ok, gaussians} <- decode_gaussians(body, parsed) do
      {:ok, GaussianCloud.new(gaussians, metadata: ply_metadata(parsed))}
    end
  end

  defp ply_metadata(parsed) do
    Metadata.new(
      comments: parsed.comments,
      entries: %{"ply_format" => to_string(parsed.format)}
    )
  end

  defp decode_vertices(body, %{format: :ascii, count: count, properties: props}) do
    lines =
      body
      |> String.split(~r/\r\n|\n|\r/, trim: true)
      |> Enum.take(count)

    if length(lines) < count do
      {:error,
       Error.new(:invalid_data,
         codec: :ply,
         message: "Expected #{count} vertices, got #{length(lines)}"
       )}
    else
      points =
        Enum.map(lines, fn line ->
          values = String.split(line) |> Enum.map(&parse_ascii_number/1)
          values_to_point(values, props)
        end)

      {:ok, points}
    end
  end

  defp decode_vertices(body, %{format: endian, count: count, properties: props})
       when endian in [:binary_le, :binary_be] do
    stride = Enum.reduce(props, 0, fn p, acc -> acc + type_size(p.type) end)
    expected = stride * count

    if byte_size(body) < expected do
      {:error,
       Error.new(:invalid_data,
         codec: :ply,
         message: "Binary PLY body too short"
       )}
    else
      {points, _} =
        Enum.map_reduce(1..count, body, fn _, rest ->
          {values, next} = unpack_row(rest, props, endian)
          {values_to_point(values, props), next}
        end)

      {:ok, points}
    end
  end

  defp decode_gaussians(body, parsed) do
    with {:ok, points} <- decode_vertices(body, parsed) do
      {:ok, Enum.map(points, &point_to_gaussian/1)}
    end
  end

  defp point_to_gaussian(%Point{} = p) do
    # Point.new/4 normalizes attribute keys to strings.
    attrs = p.attributes

    Gaussian.new({p.x, p.y, p.z},
      color: {
        Map.get(attrs, "f_dc_0", 0.5),
        Map.get(attrs, "f_dc_1", 0.5),
        Map.get(attrs, "f_dc_2", 0.5)
      },
      opacity: Map.get(attrs, "opacity", 1.0),
      scale: {
        Map.get(attrs, "scale_0", 1.0),
        Map.get(attrs, "scale_1", 1.0),
        Map.get(attrs, "scale_2", 1.0)
      },
      rotation: {
        Map.get(attrs, "rot_0", 1.0),
        Map.get(attrs, "rot_1", 0.0),
        Map.get(attrs, "rot_2", 0.0),
        Map.get(attrs, "rot_3", 0.0)
      },
      sh: extract_sh(attrs),
      metadata: attrs
    )
  end

  defp extract_sh(attrs) do
    rest_keys =
      attrs
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "f_rest_"))
      |> Enum.sort_by(fn "f_rest_" <> i -> String.to_integer(i) end)

    if rest_keys == [] do
      nil
    else
      dc = [
        Map.get(attrs, "f_dc_0", 0.0),
        Map.get(attrs, "f_dc_1", 0.0),
        Map.get(attrs, "f_dc_2", 0.0)
      ]

      rest = Enum.map(rest_keys, &Map.get(attrs, &1, 0.0))
      [dc | Enum.chunk_every(rest, 3)]
    end
  end

  defp values_to_point(values, props) do
    paired = Enum.zip(props, values) |> Map.new(fn {%{name: n}, v} -> {n, v} end)

    color =
      cond do
        Map.has_key?(paired, "alpha") and Map.has_key?(paired, "red") ->
          {trunc(paired["red"]), trunc(paired["green"]), trunc(paired["blue"]),
           trunc(paired["alpha"])}

        Map.has_key?(paired, "red") ->
          {trunc(paired["red"]), trunc(paired["green"]), trunc(paired["blue"])}

        true ->
          nil
      end

    normal =
      if Map.has_key?(paired, "nx") do
        {paired["nx"] * 1.0, paired["ny"] * 1.0, paired["nz"] * 1.0}
      else
        nil
      end

    known = ["x", "y", "z", "red", "green", "blue", "alpha", "nx", "ny", "nz"]

    attributes =
      paired
      |> Enum.reject(fn {key, _value} -> key in known end)
      |> Map.new()

    Point.new(paired["x"] || 0.0, paired["y"] || 0.0, paired["z"] || 0.0,
      color: color,
      normal: normal,
      attributes: attributes
    )
  end

  defp parse_ascii_number(str) do
    case Integer.parse(str) do
      {i, ""} ->
        i

      _ ->
        case Float.parse(str) do
          {f, _} -> f
          :error -> 0.0
        end
    end
  end

  defp unpack_row(bin, props, endian) do
    Enum.map_reduce(props, bin, fn %{type: type}, rest ->
      unpack(type, rest, endian)
    end)
  end

  defp unpack(:uchar, <<v::unsigned-integer-8, rest::binary>>, _), do: {v, rest}
  defp unpack(:char, <<v::signed-integer-8, rest::binary>>, _), do: {v, rest}

  defp unpack(:ushort, <<v::little-unsigned-integer-16, rest::binary>>, :binary_le),
    do: {v, rest}

  defp unpack(:ushort, <<v::big-unsigned-integer-16, rest::binary>>, :binary_be), do: {v, rest}
  defp unpack(:short, <<v::little-signed-integer-16, rest::binary>>, :binary_le), do: {v, rest}
  defp unpack(:short, <<v::big-signed-integer-16, rest::binary>>, :binary_be), do: {v, rest}
  defp unpack(:uint, <<v::little-unsigned-integer-32, rest::binary>>, :binary_le), do: {v, rest}
  defp unpack(:uint, <<v::big-unsigned-integer-32, rest::binary>>, :binary_be), do: {v, rest}
  defp unpack(:int, <<v::little-signed-integer-32, rest::binary>>, :binary_le), do: {v, rest}
  defp unpack(:int, <<v::big-signed-integer-32, rest::binary>>, :binary_be), do: {v, rest}
  defp unpack(:float, <<v::little-float-32, rest::binary>>, :binary_le), do: {v, rest}
  defp unpack(:float, <<v::big-float-32, rest::binary>>, :binary_be), do: {v, rest}
  defp unpack(:double, <<v::little-float-64, rest::binary>>, :binary_le), do: {v, rest}
  defp unpack(:double, <<v::big-float-64, rest::binary>>, :binary_be), do: {v, rest}

  defp type_size(:char), do: 1
  defp type_size(:uchar), do: 1
  defp type_size(:short), do: 2
  defp type_size(:ushort), do: 2
  defp type_size(:int), do: 4
  defp type_size(:uint), do: 4
  defp type_size(:float), do: 4
  defp type_size(:double), do: 8

  defp ply_format_opt(opts) do
    Keyword.get(opts, :ply_format) || Keyword.get(opts, :format, :ascii)
  end

  defp normalize_format(:ascii), do: :ascii
  defp normalize_format(:binary), do: :binary_le
  defp normalize_format(:binary_le), do: :binary_le
  defp normalize_format(:binary_be), do: :binary_be
  defp normalize_format(:little), do: :binary_le
  defp normalize_format(:big), do: :binary_be
  defp normalize_format(_), do: :ascii

  # --- Streaming helpers ----------------------------------------------------

  @header_scan_chunk 4096
  @header_max_bytes 1_048_576

  defp decode_to_list(data, opts) when is_binary(data) do
    case decode(data, opts) do
      {:ok, %PointCloud{points: points}} -> {:ok, points}
      {:ok, %GaussianCloud{gaussians: gs}} -> {:ok, gs}
      {:error, _} = err -> err
    end
  end

  defp open_ply_stream(path, opts) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        case scan_ply_header(io, "") do
          {:ok, parsed, leftover} ->
            as = resolve_as(Keyword.get(opts, :as, :auto), parsed.properties)
            {:ok, init_ply_stream_state(io, leftover, parsed, as)}

          {:error, error} ->
            File.close(io)
            {:error, error}
        end

      {:error, reason} ->
        ply_io_error(reason)
    end
  end

  defp init_ply_stream_state(io, leftover, %{format: :ascii} = parsed, as) do
    {:ascii, io, leftover, parsed, as, 0}
  end

  defp init_ply_stream_state(io, leftover, %{format: endian} = parsed, as)
       when endian in [:binary_le, :binary_be] do
    stride = Enum.reduce(parsed.properties, 0, fn p, acc -> acc + type_size(p.type) end)
    {:binary, io, leftover, endian, parsed, as, stride, 0}
  end

  defp scan_ply_header(io, acc) do
    case IO.binread(io, @header_scan_chunk) do
      data when is_binary(data) and byte_size(data) > 0 ->
        buf = acc <> data
        match_or_continue_header(io, buf)

      :eof ->
        header_eof_error(acc)

      {:error, reason} ->
        ply_io_error(reason)

      _other ->
        header_eof_error(acc)
    end
  end

  defp match_or_continue_header(io, buf) do
    case :binary.match(buf, "end_header") do
      {pos, len} ->
        header = binary_part(buf, 0, pos + len)
        rest = binary_part(buf, pos + len, byte_size(buf) - pos - len)

        with {:ok, parsed} <- parse_header(header) do
          {:ok, parsed, strip_leading_newlines(rest)}
        end

      :nomatch when byte_size(buf) > @header_max_bytes ->
        {:error,
         Error.new(:invalid_data,
           codec: :ply,
           message: "PLY header exceeds #{@header_max_bytes} bytes without end_header"
         )}

      :nomatch ->
        scan_ply_header(io, buf)
    end
  end

  defp header_eof_error("") do
    {:error, Error.new(:invalid_data, codec: :ply, message: "PLY header missing end_header")}
  end

  defp header_eof_error(acc) do
    case :binary.match(acc, "end_header") do
      {pos, len} ->
        header = binary_part(acc, 0, pos + len)
        rest = binary_part(acc, pos + len, byte_size(acc) - pos - len)

        with {:ok, parsed} <- parse_header(header) do
          {:ok, parsed, strip_leading_newlines(rest)}
        end

      :nomatch ->
        {:error, Error.new(:invalid_data, codec: :ply, message: "PLY header missing end_header")}
    end
  end

  defp next_ply_stream_item({:ok, {:binary, io, _buf, _endian, parsed, _as, _stride, i}})
       when i >= parsed.count do
    {:halt, {:done, io}}
  end

  defp next_ply_stream_item({:ok, {:binary, io, buf, endian, parsed, as, stride, i}}) do
    case take_exact_bytes(io, buf, stride) do
      {:ok, record, rest} ->
        {values, _} = unpack_row(record, parsed.properties, endian)
        item = emit_vertex(values_to_point(values, parsed.properties), as)
        {[item], {:ok, {:binary, io, rest, endian, parsed, as, stride, i + 1}}}

      {:error, error} ->
        {[{:error, error}], {:done, io}}
    end
  end

  defp next_ply_stream_item({:ok, {:ascii, io, _buf, parsed, _as, i}}) when i >= parsed.count do
    {:halt, {:done, io}}
  end

  defp next_ply_stream_item({:ok, {:ascii, io, buf, parsed, as, i}}) do
    case take_ascii_vertex_line(io, buf) do
      {:ok, line, rest} ->
        values = line |> String.split() |> Enum.map(&parse_ascii_number/1)
        item = emit_vertex(values_to_point(values, parsed.properties), as)
        {[item], {:ok, {:ascii, io, rest, parsed, as, i + 1}}}

      {:error, error} ->
        {[{:error, error}], {:done, io}}
    end
  end

  defp next_ply_stream_item({:error, error}), do: {[{:error, error}], :done}
  defp next_ply_stream_item({:done, _io}), do: {:halt, :done}
  defp next_ply_stream_item(:done), do: {:halt, :done}

  defp close_ply_stream({:ok, {:binary, io, _, _, _, _, _, _}}), do: File.close(io)
  defp close_ply_stream({:ok, {:ascii, io, _, _, _, _}}), do: File.close(io)
  defp close_ply_stream({:done, io}), do: File.close(io)
  defp close_ply_stream(_), do: :ok

  defp emit_vertex(point, :point_cloud), do: point
  defp emit_vertex(point, :gaussian_cloud), do: point_to_gaussian(point)

  defp take_exact_bytes(_io, buf, n) when byte_size(buf) >= n do
    <<chunk::binary-size(^n), rest::binary>> = buf
    {:ok, chunk, rest}
  end

  defp take_exact_bytes(io, buf, n) do
    case IO.binread(io, n - byte_size(buf)) do
      data when is_binary(data) and byte_size(data) > 0 ->
        take_exact_bytes(io, buf <> data, n)

      :eof ->
        {:error,
         Error.new(:invalid_data, codec: :ply, message: "Binary PLY body too short")}

      data when is_binary(data) ->
        {:error,
         Error.new(:invalid_data, codec: :ply, message: "Binary PLY body too short")}

      {:error, reason} ->
        ply_io_error(reason)
    end
  end

  defp take_ascii_vertex_line(io, buf) do
    case split_first_line(buf) do
      {:ok, line, rest} ->
        if String.trim(line) == "" do
          take_ascii_vertex_line(io, rest)
        else
          {:ok, String.trim(line), rest}
        end

      :incomplete ->
        read_more_ascii_line(io, buf)
    end
  end

  defp read_more_ascii_line(io, buf) do
    case IO.binread(io, @header_scan_chunk) do
      data when is_binary(data) and byte_size(data) > 0 ->
        take_ascii_vertex_line(io, buf <> data)

      :eof ->
        trimmed = String.trim(buf)

        if trimmed == "" do
          {:error,
           Error.new(:invalid_data,
             codec: :ply,
             message: "Expected more ASCII vertices"
           )}
        else
          {:ok, trimmed, ""}
        end

      {:error, reason} ->
        ply_io_error(reason)

      _other ->
        {:error,
         Error.new(:invalid_data,
           codec: :ply,
           message: "Expected more ASCII vertices"
         )}
    end
  end

  defp split_first_line(buf) do
    case :binary.match(buf, "\n") do
      {pos, 1} ->
        line = binary_part(buf, 0, pos) |> String.trim_trailing("\r")
        rest = binary_part(buf, pos + 1, byte_size(buf) - pos - 1)
        {:ok, line, rest}

      :nomatch ->
        :incomplete
    end
  end

  defp ply_io_error(reason) do
    {:error,
     Error.new(:io_error,
       codec: :ply,
       message: "Failed to read PLY file: #{inspect(reason)}",
       details: reason
     )}
  end

  defp error_stream({:error, error}), do: {[{:error, error}], :done}
  defp error_stream(:done), do: {:halt, :done}
end
