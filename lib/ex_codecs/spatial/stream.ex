defmodule ExCodecs.Spatial.Stream do
  @moduledoc """
  Stream helpers for spatial formats.

  ## What actually streams today

    * **EXCP** (`:spatial_binary`), **GSPL** (`:gsplat`), and **PLY** with
      `source: :file` (or `:auto` path detection) read the header, then one
      record/vertex at a time from disk — O(header + one record) memory.
      Binary PLY uses a fixed stride; ASCII PLY reads lines.
    * In-memory binaries still **materialize** through `decode/2`, then yield.
      A future Rust backend may memory-map large binaries.
    * **`encode_to_file/3`** with an explicit `:schema` streams EXCP/GSPL to
      disk (placeholder header, then seek-back count patch). Without `:schema`,
      encoding still collects in memory first.

  Prefer `source: :file` when the argument is a filesystem path, or
  `source: :binary` when it is an encoded payload. With `:auto` (default), a
  binary is treated as a path only when it looks path-like (under 4 KiB, no
  `ply`/`EXCP`/`GSPL` magic prefix, and contains `/` or `\\` or ends with
  `.ply`/`.excp`/`.gspl`/`.bin`) **and** `File.regular?/1` is true. A real
  file without separators/extensions is not auto-opened; a short slash-containing
  binary that happens to be a regular path may be misread as a file.
  """

  alias ExCodecs.Error
  alias ExCodecs.Spatial.Codec.{Binary, Gsplat, PLY}
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}

  @doc """
  Returns an enumerable over points or Gaussians decoded from a path or binary.

  EXCP/GSPL/PLY file sources stream incrementally; in-memory binaries still
  materialize before emitting elements.

  ## Arguments

    * `source` (`Path.t() | binary()`) — a path or complete encoded payload.
      Paths and payloads are both binaries, so `:source` controls resolution.
    * `opts` (`keyword()`) — requires `:format`: `:ply`,
      `:spatial_binary`, or `:gsplat`. `:source` may be `:auto` (default),
      `:file`, or `:binary`; PLY also accepts `:as`.

  ## Returns

  An `Enumerable.t()` yielding `%Point{}` for PLY/EXCP point clouds or
  `%Gaussian{}` for PLY/GSPL Gaussian clouds. A failure is delayed until
  enumeration and represented by exactly one
  `{:error, %ExCodecs.Error{}}` element:

    * `reason: :invalid_options` — `:format` is absent.
    * `reason: :unsupported_codec` — `:format` is unknown.
    * `reason: :io_error` — a selected file cannot be opened or read.
    * `reason: :invalid_data` — the payload is malformed, unsupported, or
      truncated.

  ## Raises / exceptions

  A missing format does not raise. `Keyword.fetch/2` and decoder option access
  raise `FunctionClauseError` when `opts` is not a proper keyword list. PLY
  source dispatch raises `FunctionClauseError` for a non-binary `source`.
  EXCP/GSPL source resolution has no clause for non-binaries and may return an
  invalid value that causes `CaseClauseError`; an unsupported `:source` value
  also raises `CaseClauseError`. Decoder exceptions may occur during
  enumeration.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.encode(PointCloud.new([Point.new(0.0, 0.0, 0.0)]), format: :ply)
      iex> [%Point{}] = ExCodecs.Spatial.Stream.decode(bin, format: :ply) |> Enum.to_list()
      iex> true
      true
  """
  @spec decode(Path.t() | binary(), keyword()) :: Enumerable.t()
  def decode(source, opts \\ []) do
    case Keyword.fetch(opts, :format) do
      :error ->
        error_stream(
          Error.new(:invalid_options,
            message: "Spatial stream_decode requires format: (e.g. format: :ply)"
          )
        )

      {:ok, format} ->
        case format do
          :ply ->
            PLY.stream_decode(source, opts)

          :spatial_binary ->
            stream_binary(source, opts)

          :gsplat ->
            stream_gsplat(source, opts)

          other ->
            error_stream(
              Error.new(:unsupported_codec,
                codec: other,
                message: "Unsupported spatial stream format: #{inspect(other)}"
              )
            )
        end
    end
  end

  @doc """
  Encodes an enumerable of points or Gaussians after collecting it in memory.

  A non-empty enumerable is classified by its first element. Empty input is
  encoded as an empty `%PointCloud{}` for PLY/EXCP and as an empty
  `%GaussianCloud{}` for GSPL.

  ## Arguments

    * `enumerable` (`Enumerable.t()`) — `%Point{}` or `%Gaussian{}` elements.
      The list should be homogeneous and contain valid struct shapes.
    * `opts` (`keyword()`) — requires `:format`: `:ply`,
      `:spatial_binary`, or `:gsplat`. Remaining keys are forwarded to
      `ExCodecs.Spatial.encode/2`.

  ## Returns

    * `{:ok, payload}` where `payload` is a `binary()`.
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` if `:format` is
      absent.
    * `{:error, %ExCodecs.Error{reason: :unsupported_codec}}` for an unknown
      format (including empty input).
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when the first item is
      an error tuple or is not a `%Point{}`/`%Gaussian{}`, when cloud and format
      are incompatible, or when codec validation fails.

  ## Raises / exceptions

  `Enum.to_list/1` raises `Protocol.UndefinedError` for a non-enumerable and
  propagates exceptions raised by enumeration. Keyword access raises
  `FunctionClauseError` for a non-keyword `opts`. Manually malformed point or
  Gaussian structs can raise codec shape/numeric exceptions; PLY converts its
  encoding exceptions to `:invalid_data`.

  ## Examples

      iex> alias ExCodecs.Spatial.Point
      iex> {:ok, bin} = ExCodecs.Spatial.Stream.encode([Point.new(1.0, 0.0, 0.0)], format: :ply)
      iex> is_binary(bin)
      true
  """
  @spec encode(Enumerable.t(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(enumerable, opts \\ []) do
    with {:ok, format} <- fetch_format(opts) do
      do_encode(enumerable, format, opts)
    end
  end

  defp fetch_format(opts) do
    case Keyword.fetch(opts, :format) do
      {:ok, format} ->
        {:ok, format}

      :error ->
        {:error,
         Error.new(:invalid_options,
           message: "Spatial stream_encode requires format: (e.g. format: :ply)"
         )}
    end
  end

  defp do_encode(enumerable, format, opts) do
    items = Enum.to_list(enumerable)

    cond do
      items == [] ->
        encode_empty(format, opts)

      match?([%Point{} | _], items) ->
        ExCodecs.Spatial.encode(PointCloud.new(items), opts)

      match?([%Gaussian{} | _], items) ->
        ExCodecs.Spatial.encode(GaussianCloud.new(items), opts)

      match?([{:error, _} | _], items) ->
        {:error, Error.new(:invalid_data, message: "Stream contained an error tuple")}

      true ->
        {:error,
         Error.new(:invalid_data,
           message: "Stream encode expects Point or Gaussian structs"
         )}
    end
  end

  @doc """
  Encodes spatial data and writes the binary to `path`.

  When `:schema` is present and `:format` is `:spatial_binary` or `:gsplat`,
  points/Gaussians are written incrementally via
  `Binary.stream_encode_to_file/3` / `Gsplat.stream_encode_to_file/3`
  (placeholder header + seek-back count). Otherwise the payload is encoded in
  memory and written with `File.write/2`.

  ## Arguments

    * `data` (`PointCloud.t() | GaussianCloud.t() | Enumerable.t()`) — a cloud,
      or an enumerable of `%Point{}`/`%Gaussian{}` values.
    * `path` (`Path.t()`) — destination path; parent directories must already
      exist.
    * `opts` (`keyword()`) — the options for `ExCodecs.Spatial.encode/2`, with
      `:format` required for enumerable input and defaulting to `:ply` for an
      already-built cloud. For streaming EXCP/GSPL writes, pass `:schema`
      (see codec docs).

  ## Returns

    * `:ok` after the complete payload is written.
    * any `:invalid_options`, `:unsupported_codec`, or `:invalid_data` error
      returned by encoding.
    * `{:error, %ExCodecs.Error{reason: :io_error, details: reason}}` when
      a file/POSIX error occurs (e.g. `:enoent`, `:eacces`, `:enospc`).

  ## Raises / exceptions

  Normal path/POSIX failures are returned. Invalid path terms or non-path
  binaries can raise `FunctionClauseError` or `ArgumentError` in the path/file
  APIs. Encoding also has the enumerable, keyword, and malformed-struct
  exceptions documented by `encode/2`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Point, PointCloud}
      iex> path = Path.join(System.tmp_dir!(), "ex_codecs_doc_#{System.unique_integer([:positive])}.ply")
      iex> :ok = ExCodecs.Spatial.Stream.encode_to_file(PointCloud.new([Point.new(0, 0, 0)]), path, format: :ply)
      iex> {:ok, "ply" <> _} = File.read(path)
      iex> File.rm!(path)
      :ok
  """
  @spec encode_to_file(Enumerable.t() | PointCloud.t() | GaussianCloud.t(), Path.t(), keyword()) ::
          :ok | {:error, Error.t()}
  def encode_to_file(data, path, opts \\ []) do
    case stream_encode_to_file_if_schema(data, path, opts) do
      :not_streaming ->
        write_encoded_payload(data, path, opts)

      result ->
        result
    end
  end

  defp stream_encode_to_file_if_schema(data, path, opts) do
    if Keyword.has_key?(opts, :schema) do
      case Keyword.get(opts, :format) do
        :spatial_binary ->
          Binary.stream_encode_to_file(enumerable_points(data), path, opts)

        :gsplat ->
          Gsplat.stream_encode_to_file(enumerable_gaussians(data), path, opts)

        other when other in [:ply, nil] ->
          {:error,
           Error.new(:invalid_options,
             message:
               "encode_to_file schema streaming requires format: :spatial_binary or :gsplat"
           )}

        other ->
          {:error,
           Error.new(:unsupported_codec,
             codec: other,
             message: "Unsupported spatial stream format: #{inspect(other)}"
           )}
      end
    else
      :not_streaming
    end
  end

  defp enumerable_points(%PointCloud{points: points}), do: points
  defp enumerable_points(enumerable), do: enumerable

  defp enumerable_gaussians(%GaussianCloud{gaussians: gs}), do: gs
  defp enumerable_gaussians(enumerable), do: enumerable

  defp write_encoded_payload(data, path, opts) do
    result =
      case data do
        %PointCloud{} -> ExCodecs.Spatial.encode(data, opts)
        %GaussianCloud{} -> ExCodecs.Spatial.encode(data, opts)
        enumerable -> encode(enumerable, opts)
      end

    case result do
      {:ok, binary} ->
        case File.write(path, binary) do
          :ok ->
            :ok

          {:error, reason} ->
            {:error,
             Error.new(:io_error,
               message: "Failed to write file: #{inspect(reason)}",
               details: reason
             )}
        end

      {:error, _} = err ->
        err
    end
  end

  defp encode_empty(:ply, opts), do: ExCodecs.Spatial.encode(PointCloud.new([]), opts)
  defp encode_empty(:spatial_binary, opts), do: ExCodecs.Spatial.encode(PointCloud.new([]), opts)
  defp encode_empty(:gsplat, opts), do: ExCodecs.Spatial.encode(GaussianCloud.new([]), opts)

  defp encode_empty(other, _) do
    {:error, Error.new(:unsupported_codec, codec: other)}
  end

  # EXCP/GSPL resolve :source and stream from disk themselves (no full File.read).
  defp stream_binary(source, opts), do: Binary.stream_decode(source, opts)
  defp stream_gsplat(source, opts), do: Gsplat.stream_decode(source, opts)

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
end
