defmodule ExCodecs.Spatial.Accel do
  @moduledoc """
  Elixir facade over the spatial Rust NIFs (EXCP, GSPL, binary PLY).

  Callers fall back to pure Elixir when `available?/0` is false or a call
  returns `:nif_not_loaded`. This module defines the **cross-language ABI**:
  row tuple shapes must match `native/ex_codecs_native/src/spatial.rs`.

  ## Chunk semantics

  Unpack NIFs return `{:ok, {rows, next_offset}}`. Pass at most `chunk_size/0`
  (4096) rows per call and advance `offset` from `next_offset`. Whole-payload
  decode paths loop the same way. A partial final record is silently skipped
  (the unpack `break`s); callers can detect truncation by comparing
  `next_offset` to the expected body size.

  ## Data coercion

  Out-of-range color bytes are **clamped** to `[0, 255]` (not wrapped). Missing
  SH coefficients are zero-filled to the declared `sh_rest` length. Both
  coercions are lossy: a round-trip through encode may not reproduce the
  original if the input contained out-of-range values.

  ## Row formats

    * EXCP point row: `{x, y, z, color, normal}` where `color` / `normal` are
      `nil` or tuples matching header flags
    * GSPL gaussian row:
      `{{x, y, z}, {r, g, b}, opacity, {sx, sy, sz}, {rw, rx, ry, rz}, sh_list}`
    * PLY binary: flat numeric lists per vertex, typed by `ply_type_tag/1`

  ## mmap

  Do not truncate or replace a file while an mmap resource from `mmap_open/1`
  is live — concurrent truncation can SIGBUS and kill the BEAM. Prefer
  `accel: false` / plain IO for untrusted paths.

  This module is intentional infrastructure; HexDocs may still group it under
  internals depending on ExDoc filters.
  """

  alias ExCodecs.Native
  alias ExCodecs.Spatial.{Gaussian, Point}

  @default_chunk 4_096
  @available_key {__MODULE__, :available}

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

  @doc """
  Returns whether spatial NIFs are loaded (cached for the VM lifetime).
  """
  @spec available?() :: boolean()
  def available? do
    case :persistent_term.get(@available_key, :unset) do
      :unset ->
        value = probe_available()
        :persistent_term.put(@available_key, value)
        value

      value when is_boolean(value) ->
        value
    end
  end

  defp probe_available do
    case safe(fn -> Native.codec_versions() end) do
      map when is_map(map) ->
        Map.has_key?(map, "spatial") or Map.has_key?(map, :spatial)

      # coveralls-ignore-start
      _ ->
        false
        # coveralls-ignore-stop
    end
  end

  @doc "Preferred max row count per unpack NIF call."
  @spec chunk_size() :: pos_integer()
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
    little? = endian in [:binary_le, :little]

    nif_chunk(
      fn -> Native.ply_binary_unpack(data, tags, little?, offset, max_count) end,
      & &1
    )
  end

  def ply_binary_unpack_mmap(resource, types, endian, offset \\ 0, max_count \\ @default_chunk) do
    tags = Enum.map(types, &ply_type_tag/1)
    little? = endian in [:binary_le, :little]

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
        [] -> []
        [[_ | _] | rest] -> List.flatten(rest)
        [h | _] = list when is_number(h) -> list |> List.flatten() |> Enum.drop(3)
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
      case e do
        %ErlangError{original: :nif_not_loaded} ->
          {:error, :nif_not_loaded}

        %ErlangError{original: other} ->
          {:error, other}

        %ArgumentError{} ->
          {:error, Exception.message(e)}

        other ->
          require Logger

          Logger.warning("ExCodecs.Spatial.Accel unexpected exception: #{inspect(other)}")

          {:error, Exception.message(other)}
      end
  end
end
