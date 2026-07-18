defmodule ExCodecs.Spatial.Accel do
  @moduledoc false

  # Thin facade over DirtyCpu spatial NIFs. Callers fall back to pure Elixir
  # when `available?/0` is false or a call returns `:nif_not_loaded`.

  alias ExCodecs.Native
  alias ExCodecs.Spatial.{Gaussian, Point}

  @default_chunk 4_096

  @ply_type_tags %{
    char: 1,
    uchar: 2,
    short: 3,
    ushort: 4,
    int: 5,
    uint: 6,
    float: 7,
    double: 8
  }

  def available? do
    case safe(fn -> Native.codec_versions() end) do
      map when is_map(map) ->
        Map.has_key?(map, "spatial") or Map.has_key?(map, :spatial)

      # coveralls-ignore-start
      _ ->
        false
        # coveralls-ignore-stop
    end
  end

  def chunk_size, do: @default_chunk

  # --- EXCP -----------------------------------------------------------------

  def excp_unpack(data, flags, offset \\ 0, max_count \\ @default_chunk)
      when is_binary(data) and is_integer(flags) do
    nif_chunk(fn -> Native.excp_unpack(data, flags, offset, max_count) end, &rows_to_points/1)
  end

  def excp_unpack_mmap(resource, flags, offset \\ 0, max_count \\ @default_chunk) do
    nif_chunk(
      fn -> Native.excp_unpack_mmap(resource, flags, offset, max_count) end,
      &rows_to_points/1
    )
  end

  def excp_pack(points, flags) when is_list(points) and is_integer(flags) do
    records = Enum.map(points, &point_to_row/1)
    nif_binary(fn -> Native.excp_pack(records, flags) end)
  rescue
    _ in [FunctionClauseError, MatchError] -> {:error, :invalid_data}
  end

  # --- GSPL -----------------------------------------------------------------

  def gspl_unpack(data, sh_rest, offset \\ 0, max_count \\ @default_chunk)
      when is_binary(data) and is_integer(sh_rest) do
    nif_chunk(
      fn -> Native.gspl_unpack(data, sh_rest, offset, max_count) end,
      &rows_to_gaussians(&1, sh_rest)
    )
  end

  def gspl_unpack_mmap(resource, sh_rest, offset \\ 0, max_count \\ @default_chunk) do
    nif_chunk(
      fn -> Native.gspl_unpack_mmap(resource, sh_rest, offset, max_count) end,
      &rows_to_gaussians(&1, sh_rest)
    )
  end

  def gspl_pack(gaussians, sh_rest) when is_list(gaussians) and is_integer(sh_rest) do
    records = Enum.map(gaussians, &gaussian_to_row(&1, sh_rest))
    nif_binary(fn -> Native.gspl_pack(records, sh_rest) end)
  rescue
    _ in [FunctionClauseError, MatchError] -> {:error, :invalid_data}
  end

  # --- Binary PLY -----------------------------------------------------------

  def ply_type_tag(type) when is_atom(type), do: Map.fetch!(@ply_type_tags, type)

  def ply_binary_unpack(data, types, endian, offset \\ 0, max_count \\ @default_chunk)
      when is_binary(data) and is_list(types) do
    tags = Enum.map(types, &ply_type_tag/1)
    little? = endian in [:binary_le, :little, true]

    nif_chunk(
      fn -> Native.ply_binary_unpack(data, tags, little?, offset, max_count) end,
      & &1
    )
  end

  def ply_binary_unpack_mmap(resource, types, endian, offset \\ 0, max_count \\ @default_chunk) do
    tags = Enum.map(types, &ply_type_tag/1)
    little? = endian in [:binary_le, :little, true]

    nif_chunk(
      fn -> Native.ply_binary_unpack_mmap(resource, tags, little?, offset, max_count) end,
      & &1
    )
  end

  # --- mmap -----------------------------------------------------------------

  def mmap_open(path) when is_binary(path) do
    case safe(fn -> Native.spatial_mmap_open(path) end) do
      {:ok, resource} -> {:ok, resource}
      {:error, _} = err -> err
    end
  end

  def mmap_len(resource) do
    case safe(fn -> Native.spatial_mmap_len(resource) end) do
      n when is_integer(n) ->
        {:ok, n}

      {:error, _} = err ->
        err

      # coveralls-ignore-start
      other ->
        {:error, {:unexpected, other}}
        # coveralls-ignore-stop
    end
  end

  def append_file(path, data) when is_binary(path) and is_binary(data) do
    case safe(fn -> Native.spatial_append_file(path, data) end) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  # --- row codecs -----------------------------------------------------------

  def point_to_row(%Point{} = p) do
    {p.x, p.y, p.z, p.color, p.normal}
  end

  def row_to_point({x, y, z, color, normal}) do
    Point.new(x, y, z, color: color, normal: normal)
  end

  def gaussian_to_row(%Gaussian{} = g, sh_rest) do
    {x, y, z} = g.position
    {r, gc, b} = g.color
    {sx, sy, sz} = g.scale
    {rw, rx, ry, rz} = g.rotation

    sh =
      case g.sh do
        nil -> []
        [_dc | rest] -> List.flatten(rest)
        list when is_list(list) -> list |> List.flatten() |> Enum.drop(3)
      end
      |> then(fn vals ->
        vals
        |> Stream.concat(Stream.cycle([0.0]))
        |> Enum.take(sh_rest)
      end)

    {{x, y, z}, {r, gc, b}, g.opacity, {sx, sy, sz}, {rw, rx, ry, rz}, sh}
  end

  def row_to_gaussian(
        {{x, y, z}, {r, gc, b}, opacity, {sx, sy, sz}, {rw, rx, ry, rz}, sh_vals},
        sh_rest
      ) do
    sh =
      if sh_rest == 0 do
        nil
      else
        [[r, gc, b] | Enum.chunk_every(sh_vals, 3)]
      end

    Gaussian.new({x, y, z},
      color: {r, gc, b},
      opacity: opacity,
      scale: {sx, sy, sz},
      rotation: {rw, rx, ry, rz},
      sh: sh
    )
  end

  defp rows_to_points(rows), do: Enum.map(rows, &row_to_point/1)

  defp rows_to_gaussians(rows, sh_rest),
    do: Enum.map(rows, &row_to_gaussian(&1, sh_rest))

  defp nif_chunk(fun, map_rows) do
    case safe(fun) do
      {:ok, {rows, next_offset}} when is_list(rows) and is_integer(next_offset) ->
        {:ok, {map_rows.(rows), next_offset}}

      {:error, _} = err ->
        err

      # coveralls-ignore-start
      other ->
        {:error, {:unexpected, other}}
        # coveralls-ignore-stop
    end
  end

  defp nif_binary(fun) do
    case safe(fun) do
      {:ok, bin} when is_binary(bin) ->
        {:ok, bin}

      {:error, _} = err ->
        err

      # coveralls-ignore-start
      other ->
        {:error, {:unexpected, other}}
        # coveralls-ignore-stop
    end
  end

  defp safe(fun) do
    fun.()
  rescue
    e ->
      # Rustler may raise ArgumentError for bad resources; that is not always an
      # `%ErlangError{}`, so discriminate on the struct rather than `rescue in`.
      case e do
        # coveralls-ignore-start
        %ErlangError{original: :nif_not_loaded} ->
          {:error, :nif_not_loaded}

        %ErlangError{original: other} ->
          {:error, other}

        # coveralls-ignore-stop
        other ->
          {:error, Exception.message(other)}
      end
  end
end
