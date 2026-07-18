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
  alias ExCodecs.Spatial.Accel
  alias ExCodecs.Spatial.Codec.StreamSource
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

    * `data` (`GaussianCloud.t()`)  -  a cloud of valid `%Gaussian{}` structs.
      Each Gaussian has position/color/scale 3-tuples, a rotation 4-tuple,
      numeric opacity, and optional SH data shaped as `[dc | rest]` (nested
      rest lists are flattened).
    * `opts` (`keyword()`)  -  reserved and currently ignored.

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

  def encode(%GaussianCloud{gaussians: gaussians}, opts) do
    sh_rest = max_sh_rest(gaussians)
    flags = if sh_rest > 0, do: 1, else: 0

    header =
      <<@magic::binary, @version::little-unsigned-16, flags::little-unsigned-16,
        length(gaussians)::little-unsigned-64, sh_rest::little-unsigned-16>>

    body = encode_gaussians_body(gaussians, sh_rest, opts)
    {:ok, header <> body}
  end

  def encode(_, _) do
    {:error,
     Error.new(:invalid_data, codec: :gsplat, message: "GSPLAT encode expects a GaussianCloud")}
  end

  @doc """
  Streams `%Gaussian{}` values to a GSPL file using an explicit schema.

  Writes a placeholder header, encodes each Gaussian as it arrives, then seeks
  back to patch the final count. Peak memory is O(one Gaussian).

  ## Arguments

    * `enumerable` (`Enumerable.t()`)  -  `%Gaussian{}` elements.
    * `path` (`Path.t()`)  -  destination file path.
    * `opts` (`keyword()`)  -  requires `:schema`. Use `[]` / `%{}` for no SH
      rest coefficients, or `[sh_rest: n]` / `%{sh_rest: n}` for `n` shared
      rest floats per Gaussian (shorter lists are zero-padded).

  ## Returns

    * `:ok`
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` when `:schema` is
      missing or invalid
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when an element is not
      a `%Gaussian{}`
    * `{:error, %ExCodecs.Error{reason: :io_error}}` on file failures

  ## Raises / exceptions

  Schema and non-`%Gaussian{}` element failures are returned. Invalid path terms
  or non-keyword `opts` can raise `FunctionClauseError` or `ArgumentError` in
  the path/file/keyword APIs. Malformed Gaussian field shapes can raise during
  bitstring construction (same class of exceptions as `encode/2`).

  ## Examples

      iex> alias ExCodecs.Spatial.{Gaussian, Codec.Gsplat}
      iex> path = Path.join(System.tmp_dir!(), "gspl_enc_#{System.unique_integer([:positive])}.gspl")
      iex> :ok = Gsplat.stream_encode_to_file([Gaussian.new({0, 0, 0})], path, schema: [])
      iex> {:ok, <<"GSPL", _::binary>>} = File.read(path)
      iex> File.rm!(path)
      :ok
  """
  @spec stream_encode_to_file(Enumerable.t(), Path.t(), keyword()) :: :ok | {:error, Error.t()}
  def stream_encode_to_file(enumerable, path, opts \\ []) do
    with {:ok, sh_rest} <- fetch_schema_sh_rest(opts),
         {:ok, io} <- open_write(path) do
      flags = if sh_rest > 0, do: 1, else: 0

      try do
        with :ok <- binwrite(io, gspl_header(flags, 0, sh_rest)),
             {:ok, count} <- write_gaussian_chunks(enumerable, io, sh_rest, opts),
             {:ok, _} <- :file.position(io, 0),
             :ok <- binwrite(io, gspl_header(flags, count, sh_rest)) do
          :ok
        else
          {:error, %Error{}} = err -> err
          {:error, reason} -> io_error(reason)
        end
      catch
        {:bad_gaussian, other} ->
          {:error,
           Error.new(:invalid_data,
             codec: :gsplat,
             message: "GSPL stream encode expects Gaussian structs, got: #{inspect(other)}"
           )}
      after
        File.close(io)
      end
    end
  end

  defp fetch_schema_sh_rest(opts) do
    case Keyword.fetch(opts, :schema) do
      :error ->
        {:error,
         Error.new(:invalid_options,
           codec: :gsplat,
           message: "GSPL stream_encode_to_file requires schema: (e.g. schema: [sh_rest: 0])"
         )}

      {:ok, schema} ->
        schema_to_sh_rest(schema)
    end
  end

  defp schema_to_sh_rest(schema) when is_list(schema) do
    sh_rest = Keyword.get(schema, :sh_rest, 0)
    unknown = Enum.reject(schema, &known_gspl_schema_entry?/1)

    cond do
      unknown != [] ->
        {:error,
         Error.new(:invalid_options,
           codec: :gsplat,
           message: "Unknown GSPL schema entries: #{inspect(unknown)}"
         )}

      not is_integer(sh_rest) or sh_rest < 0 ->
        {:error,
         Error.new(:invalid_options,
           codec: :gsplat,
           message: "schema sh_rest must be a non-negative integer"
         )}

      true ->
        {:ok, sh_rest}
    end
  end

  defp schema_to_sh_rest(schema) when is_map(schema) do
    schema_to_sh_rest(Map.to_list(schema))
  end

  defp schema_to_sh_rest(other) do
    {:error,
     Error.new(:invalid_options,
       codec: :gsplat,
       message: "GSPL schema must be a list or map, got: #{inspect(other)}"
     )}
  end

  defp known_gspl_schema_entry?(:sh_rest), do: true
  defp known_gspl_schema_entry?({:sh_rest, _}), do: true
  defp known_gspl_schema_entry?(_), do: false

  defp gspl_header(flags, count, sh_rest) do
    <<@magic::binary, @version::little-unsigned-16, flags::little-unsigned-16,
      count::little-unsigned-64, sh_rest::little-unsigned-16>>
  end

  defp open_write(path) do
    case File.open(path, [:write, :binary, :raw, :read]) do
      {:ok, io} -> {:ok, io}
      {:error, reason} -> io_error(reason)
    end
  end

  @doc """
  Decodes a GSPL version 1 payload into a Gaussian cloud.

  The decoder reads the header and declared record count described by
  `encode/2`. When the shared SH-rest count is nonzero, each decoded
  Gaussian's `sh` is `[[r, g, b] | Enum.chunk_every(rest, 3)]`; otherwise it
  is `nil`. Trailing bytes and unknown flag bits are currently ignored.
  Decoded cloud metadata contains `%{"format" => "gsplat", "version" => 1}`.

  ## Arguments

    * `data` (`binary()`)  -  a complete GSPL payload.
    * `opts` (`keyword()`)  -  reserved and currently ignored.

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
        opts
      ) do
    if version != @version do
      {:error,
       Error.new(:invalid_data,
         codec: :gsplat,
         message: "Unsupported GSPLAT version #{version}"
       )}
    else
      with {:ok, gaussians, _} <- decode_gaussians(rest, count, sh_rest, opts) do
        meta = Metadata.new(entries: %{"format" => "gsplat", "version" => version})
        {:ok, GaussianCloud.new(gaussians, metadata: meta)}
      end
    end
  end

  def decode(_, _) do
    {:error, Error.new(:invalid_data, codec: :gsplat, message: "Invalid GSPLAT binary")}
  end

  @doc """
  Returns an enumerable over Gaussians in a GSPL payload or file.

  ## Streaming behavior

    * `source: :file` (or `:auto` path detection): header then chunked
      records  -  Rust mmap + DirtyCpu unpack when available, otherwise
      `IO.binread/2` per record.
    * `source: :binary`: chunked Rust unpack when available; otherwise
      materializes through `decode/2`.

  Prefer `source: :file` for multi-MB / multi-GB `.gspl` paths.
  Pass `accel: false` to force the pure-Elixir path.

  ## Arguments

    * `source` (`Path.t() | binary()`)  -  filesystem path or complete GSPL
      payload. Both are binaries, so `:source` controls resolution.
    * `opts` (`keyword()`)  -  `:source` may be `:binary` (default), `:file`, or
      `:auto`. Prefer `:file` for paths and `:binary` for payloads; `:auto` is
      opt-in path sniffing (see `docs/spatial_formats.md`).
      `:binary`.

  ## Returns

  An `Enumerable.t()` yielding `%Gaussian{}` values. Failures are delayed until
  enumeration as exactly one `{:error, %ExCodecs.Error{}}`:

    * `reason: :io_error`  -  the file cannot be opened or read
    * `reason: :invalid_data`  -  bad magic/version, truncated header, or a
      truncated record mid-stream (`codec: :gsplat`)

  ## Raises / exceptions

  Raises `FunctionClauseError` when `source` is not a binary. Unsupported
  `:source` values raise `CaseClauseError`.

  ## Examples

      iex> alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
      iex> {:ok, bin} = ExCodecs.Spatial.Codec.Gsplat.encode(GaussianCloud.new([Gaussian.new({0, 0, 0})]))
      iex> [%Gaussian{opacity: 1.0}] =
      ...>   ExCodecs.Spatial.Codec.Gsplat.stream_decode(bin) |> Enum.to_list()
  """
  @spec stream_decode(Path.t() | binary(), keyword()) :: Enumerable.t()
  def stream_decode(source, opts \\ [])

  def stream_decode(data, opts) when is_binary(data) do
    case StreamSource.resolve(data, opts, :gsplat, &path_like?/1) do
      {:ok, :binary, bin} ->
        stream_from_binary(bin, opts)

      {:ok, :file, path} ->
        Stream.resource(
          fn -> open_gspl_file(path, opts) end,
          &next_gspl_item/1,
          &close_gspl_file/1
        )

      {:error, error} ->
        error_stream(error)
    end
  end

  defp stream_from_binary(bin, opts) do
    if accel?(opts) do
      stream_from_binary_accel(bin)
    else
      case decode(bin, Keyword.put(opts, :accel, false)) do
        {:ok, %GaussianCloud{gaussians: gs}} ->
          Stream.map(gs, & &1)

        {:error, error} ->
          error_stream(error)
      end
    end
  end

  defp stream_from_binary_accel(
         <<@magic::binary, version::little-unsigned-16, _flags::little-unsigned-16,
           count::little-unsigned-64, sh_rest::little-unsigned-16, body::binary>>
       ) do
    if version != @version do
      error_stream(
        Error.new(:invalid_data,
          codec: :gsplat,
          message: "Unsupported GSPLAT version #{version}"
        )
      )
    else
      Stream.resource(
        fn -> {:bin, body, sh_rest, count, 0, 0} end,
        &next_gspl_accel/1,
        fn _ -> :ok end
      )
    end
  end

  defp stream_from_binary_accel(_) do
    error_stream(Error.new(:invalid_data, codec: :gsplat, message: "Invalid GSPLAT binary"))
  end

  defp path_like?(bin) do
    StreamSource.path_like?(bin, &String.starts_with?(&1, @magic), [".gspl", ".bin"])
  end

  defp open_gspl_file(path, opts) do
    if accel?(opts) do
      open_gspl_mmap(path)
    else
      open_gspl_io(path)
    end
  end

  defp open_gspl_io(path) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} -> parse_gspl_header(io, IO.binread(io, 18))
      {:error, reason} -> io_error(reason)
    end
  end

  defp open_gspl_mmap(path) do
    with {:ok, header} <- read_file_prefix(path, 18),
         {:ok, ref} <- Accel.mmap_open(path),
         {:ok, state} <- mmap_state_from_header(ref, header) do
      state
    else
      # coveralls-ignore-start
      {:error, :nif_not_loaded} ->
        open_gspl_io(path)

      # coveralls-ignore-stop
      {:error, reason} when is_atom(reason) ->
        io_error(reason)

      {:error, %Error{}} = err ->
        err

      # coveralls-ignore-start
      {:error, other} ->
        io_error(other)
        # coveralls-ignore-stop
    end
  end

  defp mmap_state_from_header(
         ref,
         <<@magic::binary, version::little-unsigned-16, _flags::little-unsigned-16,
           count::little-unsigned-64, sh_rest::little-unsigned-16>>
       ) do
    if version != @version do
      {:error,
       Error.new(:invalid_data,
         codec: :gsplat,
         message: "Unsupported GSPLAT version #{version}"
       )}
    else
      {:ok, {:mmap, ref, sh_rest, count, 18, 0}}
    end
  end

  defp mmap_state_from_header(_ref, _header) do
    {:error, Error.new(:invalid_data, codec: :gsplat, message: "Invalid GSPLAT binary")}
  end

  defp read_file_prefix(path, n) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        data = IO.binread(io, n)
        File.close(io)

        case data do
          bin when is_binary(bin) ->
            {:ok, bin}

          :eof ->
            {:ok, <<>>}

          # coveralls-ignore-start
          {:error, reason} ->
            {:error, reason}
            # coveralls-ignore-stop
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_gspl_header(
         io,
         <<@magic::binary, version::little-unsigned-16, _flags::little-unsigned-16,
           count::little-unsigned-64, sh_rest::little-unsigned-16>>
       ) do
    if version != @version do
      File.close(io)

      {:error,
       Error.new(:invalid_data,
         codec: :gsplat,
         message: "Unsupported GSPLAT version #{version}"
       )}
    else
      {:ok, io, sh_rest, count, record_stride(sh_rest), 0}
    end
  end

  defp parse_gspl_header(io, :eof) do
    File.close(io)
    {:error, Error.new(:invalid_data, codec: :gsplat, message: "Invalid GSPLAT binary")}
  end

  defp parse_gspl_header(io, data) when is_binary(data) do
    File.close(io)
    {:error, Error.new(:invalid_data, codec: :gsplat, message: "Invalid GSPLAT binary")}
  end

  # coveralls-ignore-start
  defp parse_gspl_header(io, {:error, reason}) do
    File.close(io)
    io_error(reason)
  end

  # coveralls-ignore-stop

  defp next_gspl_item({:ok, io, _sh_rest, count, _stride, i}) when i >= count do
    {:halt, {:done, io}}
  end

  defp next_gspl_item({:ok, io, sh_rest, count, stride, i}) do
    case IO.binread(io, stride) do
      data when is_binary(data) and byte_size(data) == stride ->
        case decode_gaussian(data, sh_rest) do
          {:ok, gaussian, _} ->
            {[gaussian], {:ok, io, sh_rest, count, stride, i + 1}}

          # coveralls-ignore-start
          {:error, error} ->
            {[{:error, error}], {:done, io}}
            # coveralls-ignore-stop
        end

      :eof ->
        {[
           {:error, Error.new(:invalid_data, codec: :gsplat, message: "Truncated Gaussian record")}
         ], {:done, io}}

      data when is_binary(data) ->
        {[
           {:error, Error.new(:invalid_data, codec: :gsplat, message: "Truncated Gaussian record")}
         ], {:done, io}}

      # coveralls-ignore-start
      {:error, reason} ->
        {[{:error, io_error_struct(reason)}], {:done, io}}
        # coveralls-ignore-stop
    end
  end

  defp next_gspl_item({:mmap, _, _, count, _, i}) when i >= count, do: {:halt, :done_mmap}

  defp next_gspl_item({:mmap, ref, sh_rest, count, offset, i}) do
    next_gspl_accel({:mmap, ref, sh_rest, count, offset, i})
  end

  defp next_gspl_item({:error, error}), do: {[{:error, error}], :done}
  defp next_gspl_item({:done, _io}), do: {:halt, :done}
  defp next_gspl_item(:done), do: {:halt, :done}
  # coveralls-ignore-start
  defp next_gspl_item(:done_mmap), do: {:halt, :done}

  defp next_gspl_accel(:done), do: {:halt, :done}
  defp next_gspl_accel(:done_mmap), do: {:halt, :done}
  # coveralls-ignore-stop

  defp next_gspl_accel({:bin, _body, _sh_rest, count, _offset, i}) when i >= count do
    {:halt, :done}
  end

  defp next_gspl_accel({:bin, body, sh_rest, count, offset, i}) do
    want = min(Accel.chunk_size(), count - i)

    case Accel.gspl_unpack(body, sh_rest, offset, want) do
      {:ok, {[], _}} when want > 0 ->
        {[
           {:error,
            Error.new(:invalid_data,
              codec: :gsplat,
              message: "Truncated Gaussian record"
            )}
         ], :done}

      {:ok, {gaussians, next}} ->
        {gaussians, {:bin, body, sh_rest, count, next, i + length(gaussians)}}

      # coveralls-ignore-start
      {:error, :nif_not_loaded} ->
        {[
           {:error,
            Error.new(:nif_not_loaded,
              codec: :gsplat,
              message: "Spatial NIF unavailable mid-stream"
            )}
         ], :done}

      {:error, _} ->
        {[
           {:error,
            Error.new(:invalid_data,
              codec: :gsplat,
              message: "Truncated Gaussian record"
            )}
         ], :done}

        # coveralls-ignore-stop
    end
  end

  # coveralls-ignore-start
  defp next_gspl_accel({:mmap, _ref, _sh_rest, count, _offset, i}) when i >= count do
    {:halt, :done_mmap}
  end

  # coveralls-ignore-stop

  defp next_gspl_accel({:mmap, ref, sh_rest, count, offset, i}) do
    want = min(Accel.chunk_size(), count - i)

    case Accel.gspl_unpack_mmap(ref, sh_rest, offset, want) do
      {:ok, {[], _}} when want > 0 ->
        {[
           {:error,
            Error.new(:invalid_data,
              codec: :gsplat,
              message: "Truncated Gaussian record"
            )}
         ], :done_mmap}

      {:ok, {gaussians, next}} ->
        {gaussians, {:mmap, ref, sh_rest, count, next, i + length(gaussians)}}

      # coveralls-ignore-start
      {:error, _} ->
        {[
           {:error,
            Error.new(:invalid_data,
              codec: :gsplat,
              message: "Truncated Gaussian record"
            )}
         ], :done_mmap}

        # coveralls-ignore-stop
    end
  end

  defp close_gspl_file({:ok, io, _, _, _, _}), do: File.close(io)
  defp close_gspl_file({:done, io}), do: File.close(io)
  defp close_gspl_file(_), do: :ok

  defp record_stride(sh_rest), do: 56 + sh_rest * 4

  defp io_error(reason), do: {:error, io_error_struct(reason)}

  defp io_error_struct(reason) do
    Error.new(:io_error,
      codec: :gsplat,
      message: "Failed to read GSPL file: #{inspect(reason)}",
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

  defp max_sh_rest(gaussians) do
    gaussians
    |> Enum.map(fn
      %{sh: nil} -> 0
      %{sh: []} -> 0
      %{sh: [[_ | _] | rest]} -> length(List.flatten(rest))
      %{sh: [h | _] = other} when is_number(h) -> max(length(List.flatten(other)) - 3, 0)
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
  defp sh_rest_values([]), do: []
  defp sh_rest_values([[_ | _] | rest]), do: List.flatten(rest)
  defp sh_rest_values([h | _] = list) when is_number(h), do: list |> List.flatten() |> Enum.drop(3)

  defp encode_gaussians_body(gaussians, sh_rest, opts) do
    if accel?(opts) do
      case Accel.gspl_pack(gaussians, sh_rest) do
        {:ok, bin} ->
          bin

        # coveralls-ignore-start
        _ ->
          encode_gaussians_body_elixir(gaussians, sh_rest)
          # coveralls-ignore-stop
      end
    else
      encode_gaussians_body_elixir(gaussians, sh_rest)
    end
  end

  defp encode_gaussians_body_elixir(gaussians, sh_rest) do
    IO.iodata_to_binary(Enum.map(gaussians, fn g -> encode_gaussian(g, sh_rest) end))
  end

  defp write_gaussian_chunks(enumerable, io, sh_rest, opts) do
    chunk_size = if accel?(opts), do: Accel.chunk_size(), else: 1

    enumerable
    |> Stream.chunk_every(chunk_size)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, n} ->
      gaussians = assert_gaussians!(chunk)

      case write_gaussian_chunk(io, gaussians, sh_rest, opts) do
        :ok -> {:cont, {:ok, n + length(gaussians)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp assert_gaussians!(chunk) do
    Enum.map(chunk, fn
      %Gaussian{} = g -> g
      other -> throw({:bad_gaussian, other})
    end)
  end

  defp write_gaussian_chunk(io, gaussians, sh_rest, opts) do
    if accel?(opts) do
      case Accel.gspl_pack(gaussians, sh_rest) do
        {:ok, bin} ->
          binwrite(io, bin)

        # coveralls-ignore-start
        _ ->
          write_gaussians_elixir(io, gaussians, sh_rest)
          # coveralls-ignore-stop
      end
    else
      write_gaussians_elixir(io, gaussians, sh_rest)
    end
  end

  defp write_gaussians_elixir(io, gaussians, sh_rest) do
    Enum.reduce_while(gaussians, :ok, fn g, :ok ->
      case binwrite(io, encode_gaussian(g, sh_rest)) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp binwrite(io, data) do
    case :file.write(io, data) do
      :ok -> :ok
      {:error, reason} -> io_error(reason)
    end
  end

  defp accel?(opts), do: StreamSource.accel?(opts)

  defp decode_gaussians(bin, 0, _sh_rest, _opts), do: {:ok, [], bin}

  defp decode_gaussians(bin, count, sh_rest, opts) do
    if accel?(opts) do
      decode_gaussians_accel(bin, count, sh_rest, 0, 0, [])
    else
      decode_gaussians_elixir(bin, count, sh_rest)
    end
  end

  defp decode_gaussians_accel(_bin, count, _sh_rest, _offset, i, acc) when i >= count do
    {:ok, Enum.reverse(acc), <<>>}
  end

  defp decode_gaussians_accel(bin, count, sh_rest, offset, i, acc) do
    want = min(Accel.chunk_size(), count - i)

    case Accel.gspl_unpack(bin, sh_rest, offset, want) do
      {:ok, {gaussians, next}} when length(gaussians) == want ->
        decode_gaussians_accel(
          bin,
          count,
          sh_rest,
          next,
          i + want,
          Enum.reverse(gaussians, acc)
        )

      # Incomplete / failed Accel unpack: Elixir path preserves "Truncated SH"
      # and other field-specific messages, resuming at remaining bytes.
      _ ->
        rest = binary_part(bin, offset, byte_size(bin) - offset)

        case decode_gaussians_elixir(rest, count - i, sh_rest) do
          {:ok, gs, leftover} -> {:ok, Enum.reverse(acc, gs), leftover}
          {:error, _} = err -> err
        end
    end
  end

  defp decode_gaussians_elixir(bin, count, sh_rest) do
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
