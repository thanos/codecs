defmodule ExCodecs.Spatial.Codec.Gsplat do
  @moduledoc """
  Simple little-endian binary format for Gaussian splat clouds.

  ## Layout

      magic:   "GSPL" (4 bytes)
      version: u16 LE = 1
      flags:   u16 LE  (bit0 = has SH rest coeffs count in header)
      count:   u64 LE
      sh_rest: u16 LE  (number of f_rest floats per Gaussian; 0 if none)
      records: count × record

  Each record:

      position:  3 × f32
      color:     3 × f32   (f_dc)
      opacity:   f32
      scale:     3 × f32
      rotation:  4 × f32   (w, x, y, z)
      sh_rest:   sh_rest × f32 (optional)
  """

  alias ExCodecs.Error
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Metadata}

  @magic "GSPL"
  @version 1

  @doc """
  Encodes a Gaussian cloud in the GSPL version 1 binary format.

  The 18-byte header contains `"GSPL"`, version `u16` little-endian, flags
  `u16` little-endian, Gaussian count `u64` little-endian, and a shared
  spherical-harmonic-rest count `u16` little-endian. Each record contains 14
  little-endian `f32` values: position XYZ, DC color RGB, opacity, scale XYZ,
  and quaternion rotation `(w, x, y, z)`, followed by the shared number of
  little-endian `f32` SH-rest values.

  The shared SH count is the longest flattened rest coefficient list in the
  cloud; shorter lists are padded with zero. The DC coefficient is represented
  by `Gaussian.color`. Gaussian metadata and cloud-level metadata are not
  stored.

  ## Arguments

    * `data` (`GaussianCloud.t()`) — a cloud of valid `%Gaussian{}` structs.
      Each Gaussian has position/color/scale 3-tuples, a rotation 4-tuple,
      numeric opacity, and optional SH data shaped as `[dc | rest]` (nested
      rest lists are flattened).
    * `opts` (`keyword()`) — reserved and currently ignored.

  ## Returns

    * `{:ok, payload}` where `payload` is a GSPL `binary()`.
    * `{:error, %ExCodecs.Error{reason: :invalid_data, codec: :gsplat}}` when
      `data` is not a `%GaussianCloud{}`.

  ## Raises / exceptions

  A wrong top-level type is returned as `:invalid_data`, and `opts` is ignored.
  Manually malformed cloud/Gaussian structs can raise `FunctionClauseError`,
  `MatchError`, `ArgumentError`, `ArithmeticError`, or a bitstring construction
  exception for invalid SH shapes, tuple shapes, counts, or non-numeric values.

  ## Examples

      iex> alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
      iex> cloud = GaussianCloud.new([Gaussian.new({0, 0, 0}, opacity: 0.75)])
      iex> {:ok, <<"GSPL", 1::little-16, _flags::little-16, 1::little-64,
      ...>          0::little-16, _record::binary>>} =
      ...>   ExCodecs.Spatial.Codec.Gsplat.encode(cloud)
      iex> true
      true
  """
  @spec encode(GaussianCloud.t(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(data, opts \\ [])

  def encode(%GaussianCloud{gaussians: gaussians}, _opts) do
    sh_rest = max_sh_rest(gaussians)
    flags = if sh_rest > 0, do: 1, else: 0

    header =
      <<@magic::binary, @version::little-unsigned-16, flags::little-unsigned-16,
        length(gaussians)::little-unsigned-64, sh_rest::little-unsigned-16>>

    body =
      IO.iodata_to_binary(Enum.map(gaussians, fn g -> encode_gaussian(g, sh_rest) end))

    {:ok, header <> body}
  end

  def encode(_, _) do
    {:error,
     Error.new(:invalid_data, codec: :gsplat, message: "GSPLAT encode expects a GaussianCloud")}
  end

  @doc """
  Decodes a GSPL version 1 payload into a Gaussian cloud.

  The decoder reads the header and declared record count described by
  `encode/2`. When the shared SH-rest count is nonzero, each decoded
  Gaussian's `sh` is `[[r, g, b] | Enum.chunk_every(rest, 3)]`; otherwise it
  is `nil`. Trailing bytes and unknown flag bits are currently ignored.
  Decoded cloud metadata contains `%{"format" => "gsplat", "version" => 1}`.

  ## Arguments

    * `data` (`binary()`) — a complete GSPL payload.
    * `opts` (`keyword()`) — reserved and currently ignored.

  ## Returns

    * `{:ok, %GaussianCloud{}}`
    * `{:error, %ExCodecs.Error{reason: :invalid_data, codec: :gsplat}}` when
      the magic/header is invalid or too short, the version is not 1, a
      declared 14-float record is truncated, or its declared SH-rest values
      are truncated.

  ## Raises / exceptions

  The external payload failures above are returned. `opts` is ignored, and
  non-binary input is handled by the catch-all clause as `:invalid_data`; this
  function does not intentionally raise for external payloads.

  ## Examples

      iex> alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.Codec.Gsplat.encode(GaussianCloud.new([Gaussian.new({1.0, 0.0, 0.0})]))
      iex> {:ok, %GaussianCloud{gaussians: [g]}} = ExCodecs.Spatial.Codec.Gsplat.decode(bin)
      iex> elem(g.position, 0)
      1.0
  """
  @spec decode(binary(), keyword()) :: {:ok, GaussianCloud.t()} | {:error, Error.t()}
  def decode(data, opts \\ [])

  def decode(
        <<@magic::binary, version::little-unsigned-16, _flags::little-unsigned-16,
          count::little-unsigned-64, sh_rest::little-unsigned-16, rest::binary>>,
        _opts
      ) do
    if version != @version do
      {:error,
       Error.new(:invalid_data,
         codec: :gsplat,
         message: "Unsupported GSPLAT version #{version}"
       )}
    else
      with {:ok, gaussians, _} <- decode_gaussians(rest, count, sh_rest) do
        meta = Metadata.new(entries: %{"format" => "gsplat", "version" => version})
        {:ok, GaussianCloud.new(gaussians, metadata: meta)}
      end
    end
  end

  def decode(_, _) do
    {:error, Error.new(:invalid_data, codec: :gsplat, message: "Invalid GSPLAT binary")}
  end

  @doc """
  Returns an enumerable over Gaussians in a GSPL payload.

  ## Arguments

    * `data` (`binary()`) — a complete GSPL payload.
    * `opts` (`keyword()`) — reserved and currently ignored.

  ## Returns

  An `Enumerable.t()` that yields decoded `%Gaussian{}` structs after the
  complete cloud has been materialized. If `decode/2` fails, it yields exactly
  one `{:error, %ExCodecs.Error{reason: :invalid_data, codec: :gsplat}}`
  element.

  ## Raises / exceptions

  Raises `FunctionClauseError` when `data` is not a binary because this public
  function is guarded. `opts` is ignored. Binary validation failures are
  delayed as the single error element rather than raised.

  ## Examples

      iex> alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.Codec.Gsplat.encode(GaussianCloud.new([Gaussian.new({0, 0, 0})]))
      iex> [%Gaussian{opacity: 1.0}] =
      ...>   ExCodecs.Spatial.Codec.Gsplat.stream_decode(bin) |> Enum.to_list()
  """
  @spec stream_decode(binary(), keyword()) :: Enumerable.t()
  def stream_decode(data, opts \\ []) when is_binary(data) do
    case decode(data, opts) do
      {:ok, %GaussianCloud{gaussians: gs}} ->
        Stream.map(gs, & &1)

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

  defp max_sh_rest(gaussians) do
    gaussians
    |> Enum.map(fn
      %{sh: nil} -> 0
      %{sh: [_dc | rest]} -> length(List.flatten(rest))
      %{sh: other} when is_list(other) -> max(length(List.flatten(other)) - 3, 0)
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp encode_gaussian(%Gaussian{} = g, sh_rest) do
    {x, y, z} = g.position
    {r, gc, b} = g.color
    {sx, sy, sz} = g.scale
    {rw, rx, ry, rz} = g.rotation

    base =
      <<x::little-float-32, y::little-float-32, z::little-float-32, r::little-float-32,
        gc::little-float-32, b::little-float-32, g.opacity::little-float-32, sx::little-float-32,
        sy::little-float-32, sz::little-float-32, rw::little-float-32, rx::little-float-32,
        ry::little-float-32, rz::little-float-32>>

    rest =
      g.sh
      |> sh_rest_values()
      |> then(fn vals ->
        vals
        |> Stream.concat(Stream.cycle([0.0]))
        |> Enum.take(sh_rest)
      end)
      |> Enum.map(fn v -> <<v::little-float-32>> end)
      |> IO.iodata_to_binary()

    base <> rest
  end

  defp sh_rest_values(nil), do: []
  defp sh_rest_values([_dc | rest]), do: List.flatten(rest)
  defp sh_rest_values(list) when is_list(list), do: list |> List.flatten() |> Enum.drop(3)

  defp decode_gaussians(bin, 0, _sh_rest), do: {:ok, [], bin}

  defp decode_gaussians(bin, count, sh_rest) do
    Enum.reduce_while(1..count, {:ok, [], bin}, fn _, {:ok, acc, rest} ->
      case decode_gaussian(rest, sh_rest) do
        {:ok, g, next} -> {:cont, {:ok, [g | acc], next}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, gs, rest} -> {:ok, Enum.reverse(gs), rest}
      other -> other
    end
  end

  defp decode_gaussian(
         <<x::little-float-32, y::little-float-32, z::little-float-32, r::little-float-32,
           gc::little-float-32, b::little-float-32, opacity::little-float-32, sx::little-float-32,
           sy::little-float-32, sz::little-float-32, rw::little-float-32, rx::little-float-32,
           ry::little-float-32, rz::little-float-32, rest::binary>>,
         sh_rest
       ) do
    case take_floats(rest, sh_rest) do
      {:ok, sh_vals, next} ->
        sh =
          if sh_rest == 0 do
            nil
          else
            [[r, gc, b] | Enum.chunk_every(sh_vals, 3)]
          end

        g =
          Gaussian.new({x, y, z},
            color: {r, gc, b},
            opacity: opacity,
            scale: {sx, sy, sz},
            rotation: {rw, rx, ry, rz},
            sh: sh
          )

        {:ok, g, next}

      {:error, _} = err ->
        err
    end
  end

  defp decode_gaussian(_, _) do
    {:error, Error.new(:invalid_data, codec: :gsplat, message: "Truncated Gaussian record")}
  end

  defp take_floats(bin, 0), do: {:ok, [], bin}

  defp take_floats(bin, n) do
    Enum.reduce_while(1..n, {:ok, [], bin}, fn _, {:ok, acc, rest} ->
      case rest do
        <<v::little-float-32, next::binary>> -> {:cont, {:ok, [v | acc], next}}
        _ -> {:halt, {:error, Error.new(:invalid_data, codec: :gsplat, message: "Truncated SH")}}
      end
    end)
    |> case do
      {:ok, vals, rest} -> {:ok, Enum.reverse(vals), rest}
      other -> other
    end
  end
end
