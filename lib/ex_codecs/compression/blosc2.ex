defmodule ExCodecs.Compression.Blosc2 do
  @moduledoc """
  Blosc2 **chunk** codec — C-Blosc2-compatible wire format, pure Rust.

  ## What you get (chunk only)

  ```
  binary  →  [filters]  →  [codec]  →  one Blosc2 chunk binary
  ```

  This matches python-blosc2 / C-Blosc2 **single-buffer** compress/decompress.

  ### Not included

  | Layer | Status |
  |-------|--------|
  | Super-chunk (SChunk) | No |
  | Contiguous frame (`.b2frame`) | No |
  | B2ND (N-D arrays) | No |

  For large data, split buffers yourself and store multiple chunks. Usability
  for “compress my array slice in Elixir” is full; for “Blosc2 as a database
  file format”, use python/C Blosc2.

  ## Options

    * `:cname` — `:blosclz` | `:lz4` (default) | `:lz4hc` | `:zstd` | `:zlib`
    * `:clevel` — `0..9` (default `5`)
    * `:shuffle` — `:none` | `:byte` (default) | `:bit`
    * `:typesize` — `1..255` (default `8`)
    * `:max_output_size` — Maximum allowed decompressed size in bytes
      (default: 256 MiB; also hard-capped at 1 GiB per chunk)

  ## Security

  Do not decompress untrusted inputs without a tight `:max_output_size`.

  ### Snappy

  `cname: :snappy` is **rejected**. Use standalone `ExCodecs.encode(:snappy, data)`
  or Blosc2 with `:lz4` / `:blosclz`.

  ## Implementation

  Pure-Rust `blosc2-pure-rs` (no C-Blosc2 / cmake). NIF uses single-threaded
  compression (`nthreads: 1`) on DirtyCpu.

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:blosc2, <<1, 2, 3, 4, 5, 6, 7, 8>>)
      iex> {:ok, decompressed} = ExCodecs.decode(:blosc2, compressed)
      iex> decompressed
      <<1, 2, 3, 4, 5, 6, 7, 8>>
  """

  @behaviour ExCodecs.Codec

  @default_cname :lz4
  @default_clevel 5
  @default_shuffle :byte
  @default_typesize 8

  @valid_cnames [:blosclz, :lz4, :lz4hc, :zstd, :zlib]
  @valid_shuffles [:none, :byte, :bit]

  @doc """
  Returns the registry metadata for the Blosc2 chunk codec.

  ## Arguments

  This function takes no arguments.

  ## Returns

  An `ExCodecs.Codec.t()` with these Blosc2-specific fields:

    * `name: :blosc2` and `category: :compression`
    * `module: ExCodecs.Compression.Blosc2`
    * `native?: true` because compression runs in a NIF
    * `streaming?: false` because only individual chunks are supported
    * `configurable?: true` because `encode/2` accepts compressor and filter
      options
    * `version: "c-blosc2-chunk/pure-rust"` for the compatible format and
      backend

  ## Raises / Exceptions

  This function does not invoke the NIF and does not raise.

  ## Examples

      iex> ExCodecs.Compression.Blosc2.__codec_info__()
      %ExCodecs.Codec{
        name: :blosc2,
        category: :compression,
        module: ExCodecs.Compression.Blosc2,
        native?: true,
        streaming?: false,
        configurable?: true,
        version: "c-blosc2-chunk/pure-rust"
      }
  """
  def __codec_info__ do
    %ExCodecs.Codec{
      name: :blosc2,
      category: :compression,
      module: __MODULE__,
      native?: true,
      streaming?: false,
      configurable?: true,
      version: blosc2_version()
    }
  end

  defp blosc2_version, do: "c-blosc2-chunk/pure-rust"

  @doc """
  Compresses a binary into a C-Blosc2-compatible **chunk**.

  ## Arguments

    * `data` (`binary()`) — uncompressed bytes. When shuffling, choose a
      `:typesize` matching each logical value; a whole-value multiple is
      preferred.
    * `opts` (`keyword()`) — compression settings:
      * `:cname` — `:blosclz | :lz4 | :lz4hc | :zstd | :zlib`; defaults to
        `:lz4`
      * `:clevel` — integer compression level in `0..9`; defaults to `5`
      * `:shuffle` — `:none | :byte | :bit`; defaults to `:byte`
      * `:typesize` — logical element size in bytes, integer `1..255`;
        defaults to `8`

      Unknown keys are ignored. `:snappy` is not a valid `:cname`.

  ## Returns

    * `{:ok, chunk :: binary()}` containing one Blosc2 chunk
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, `opts` is not a list, or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` for an unsupported
      `:cname` (including `:snappy`) or an out-of-range option
    * `{:error, %ExCodecs.Error{reason: :compression_failed}}` when the native
      compressor fails
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Guard/option validation failures and `ErlangError`/`ArgumentError`
  exceptions from the NIF call are converted to error tuples. Unexpected
  exception classes may propagate.

  ## Examples

      iex> samples = <<100::little-16, 101::little-16, 102::little-16>>
      iex> {:ok, chunk} =
      ...>   ExCodecs.Compression.Blosc2.encode(samples,
      ...>     cname: :zstd,
      ...>     clevel: 7,
      ...>     shuffle: :byte,
      ...>     typesize: 2
      ...>   )
      iex> ExCodecs.Compression.Blosc2.decode(chunk, [])
      {:ok, <<100::little-16, 101::little-16, 102::little-16>>}

      iex> {:error, error} =
      ...>   ExCodecs.Compression.Blosc2.encode("data", cname: :snappy)
      iex> error.reason
      :invalid_options
  """
  @impl true
  def encode(data, opts) when is_binary(data) and is_list(opts) do
    cname = Keyword.get(opts, :cname, @default_cname)
    clevel = Keyword.get(opts, :clevel, @default_clevel)
    shuffle = Keyword.get(opts, :shuffle, @default_shuffle)
    typesize = Keyword.get(opts, :typesize, @default_typesize)

    with :ok <- validate_cname(cname),
         :ok <- validate_clevel(clevel),
         :ok <- validate_shuffle(shuffle),
         :ok <- validate_typesize(typesize) do
      ExCodecs.NIF.safe_call(:blosc2, fn ->
        ExCodecs.Native.blosc2_compress(
          data,
          cname_to_int(cname),
          clevel,
          shuffle_to_int(shuffle),
          typesize
        )
      end)
    end
  end

  def encode(_data, _opts) do
    {:error, ExCodecs.Error.new(:invalid_data, codec: :blosc2)}
  end

  @doc """
  Decompresses a Blosc2 **chunk** binary.

  ## Arguments

    * `data` (`binary()`) — one chunk produced by this codec or by
      C/python-blosc2 single-buffer `compress`
    * `opts` (`term()`) — ignored by this direct function; callers using the
      codec behaviour or registry API should pass the keyword list `[]`

  ## Returns

    * `{:ok, decompressed :: binary()}` on success
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, the chunk header is shorter than 16 bytes, the declared output
      exceeds 1 GiB, or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :decompression_failed}}` when the chunk
      is corrupt, truncated, unsupported, or is a Blosc2 container rather than
      a single chunk
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Data guard failures and `ErlangError`/`ArgumentError` exceptions from the NIF
  call are converted to error tuples. Because `opts` is ignored, this direct
  function also accepts non-list option terms. Unexpected exception classes
  may propagate.

  ## Examples

      iex> payload = "one Blosc2 chunk"
      iex> {:ok, chunk} =
      ...>   ExCodecs.Compression.Blosc2.encode(payload, shuffle: :none, typesize: 1)
      iex> ExCodecs.Compression.Blosc2.decode(chunk, [])
      {:ok, "one Blosc2 chunk"}

      iex> {:error, error} = ExCodecs.Compression.Blosc2.decode("short", [])
      iex> error.reason
      :invalid_data
  """
  @impl true
  def decode(data, opts) when is_binary(data) and is_list(opts) do
    with {:ok, max} <- ExCodecs.NIF.max_output_size(opts) do
      ExCodecs.NIF.safe_call(:blosc2, fn -> ExCodecs.Native.blosc2_decompress(data, max) end)
    end
  end

  def decode(_data, _opts) do
    {:error, ExCodecs.Error.new(:invalid_data, codec: :blosc2)}
  end

  defp validate_cname(cname) when cname in @valid_cnames, do: :ok

  defp validate_cname(:snappy) do
    {:error,
     ExCodecs.Error.new(:invalid_options,
       codec: :blosc2,
       message:
         ":snappy is not a standard C-Blosc2 compressor in this build; use one of: #{inspect(@valid_cnames)}"
     )}
  end

  defp validate_cname(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options,
         message: "cname must be one of: #{inspect(@valid_cnames)}"
       )}

  defp validate_clevel(level) when is_integer(level) and level >= 0 and level <= 9, do: :ok

  defp validate_clevel(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options, message: "clevel must be an integer between 0 and 9")}

  defp validate_shuffle(shuffle) when shuffle in @valid_shuffles, do: :ok

  defp validate_shuffle(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options,
         message: "shuffle must be one of: #{inspect(@valid_shuffles)}"
       )}

  defp validate_typesize(ts) when is_integer(ts) and ts > 0 and ts <= 255, do: :ok

  defp validate_typesize(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options,
         message: "typesize must be an integer from 1 to 255"
       )}

  defp cname_to_int(:blosclz), do: 0
  defp cname_to_int(:lz4), do: 1
  defp cname_to_int(:lz4hc), do: 2
  defp cname_to_int(:zlib), do: 4
  defp cname_to_int(:zstd), do: 5

  defp shuffle_to_int(:none), do: 0
  defp shuffle_to_int(:byte), do: 1
  defp shuffle_to_int(:bit), do: 2
end
