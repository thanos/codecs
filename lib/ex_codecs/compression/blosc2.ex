defmodule ExCodecs.Compression.Blosc2 do
  @moduledoc """
  Blosc2 meta-compressor codec.

  Blosc2 is a high-performance meta-compressor designed for binary data,
  particularly numerical arrays. It can use other compressors (Zstd, LZ4, etc.)
  internally while adding features like byte/bit shuffle, multi-threading,
  and frame-based container formats.

  ## Options

    * `:cname` — Internal compressor: `:lz4`, `:lz4hc`, `:blosclz`,
      `:zstd`, `:snappy`, `:zlib` (default: `:lz4`)
    * `:clevel` — Compression level 0-9 (default: 5). 0 means no compression.
    * `:shuffle` — Shuffle filter: `:none`, `:byte`, `:bit` (default: `:byte`)
    * `:typesize` — Element size in bytes for shuffle (default: 8)
    * `:blocksize` — Block size, 0 for automatic (default: 0)
    * `:numthreads` — Number of threads, 1 for single-threaded (default: 1)

  ## Performance Characteristics

    * Optimized for numerical/array data
    * Byte/bit shuffle dramatically improves compression ratios for typed data
    * Multi-threaded compression and decompression
    * Excellent when used with appropriate typesize and shuffle settings

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:blosc2, <<1, 2, 3, 4, 5, 6, 7, 8>>)
      iex> {:ok, decompressed} = ExCodecs.decode(:blosc2, compressed)
      iex> decompressed
      <<1, 2, 3, 4, 5, 6, 7, 8>>

      iex> {:ok, compressed} = ExCodecs.encode(:blosc2, data, cname: :zstd, clevel: 5, shuffle: :byte)
      iex> is_binary(compressed)
      true

  > **Note**: Blosc2 is optimized for data whose length is a multiple of
  > `typesize`. For general-purpose binary compression, Zstd or LZ4 may be
  > more appropriate.
  """

  @behaviour ExCodecs.Codec

  @default_cname :lz4
  @default_clevel 5
  @default_shuffle :byte
  @default_typesize 8
  @default_blocksize 0
  @default_numthreads 1

  @valid_cnames [:lz4, :lz4hc, :blosclz, :zstd, :snappy, :zlib]
  @valid_shuffles [:none, :byte, :bit]

  @doc """
  Returns codec metadata for the registry.
  """
  def __codec_info__ do
    %ExCodecs.Codec{
      name: :blosc2,
      category: :compression,
      module: __MODULE__,
      native?: true,
      streaming?: true,
      configurable?: true,
      version: blosc2_version()
    }
  end

  defp blosc2_version, do: "2.x-pure-rust"

  @doc """
  Encodes (compresses) data using Blosc2.

  ## Options

    * `:cname` — Internal compressor atom (default: `:lz4`)
    * `:clevel` — Compression level 0-9 (default: 5)
    * `:shuffle` — Shuffle filter: `:none`, `:byte`, `:bit` (default: `:byte`)
    * `:typesize` — Element size in bytes (default: 8)
    * `:blocksize` — Block size, 0 for auto (default: 0)
    * `:numthreads` — Number of threads (default: 1)
  """
  @impl true
  def encode(data, opts) when is_binary(data) and is_list(opts) do
    cname = Keyword.get(opts, :cname, @default_cname)
    clevel = Keyword.get(opts, :clevel, @default_clevel)
    shuffle = Keyword.get(opts, :shuffle, @default_shuffle)
    typesize = Keyword.get(opts, :typesize, @default_typesize)
    blocksize = Keyword.get(opts, :blocksize, @default_blocksize)
    numthreads = Keyword.get(opts, :numthreads, @default_numthreads)

    with :ok <- validate_cname(cname),
         :ok <- validate_clevel(clevel),
         :ok <- validate_shuffle(shuffle),
         :ok <- validate_typesize(typesize) do
      ExCodecs.NIF.wrap(
        :blosc2,
        ExCodecs.Native.blosc2_compress(
          data,
          cname_to_int(cname),
          clevel,
          shuffle_to_int(shuffle),
          typesize,
          blocksize,
          numthreads
        )
      )
    end
  end

  @doc """
  Decodes (decompresses) Blosc2-compressed data.
  """
  @impl true
  def decode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.wrap(:blosc2, ExCodecs.Native.blosc2_decompress(data))
  end

  defp validate_cname(cname) when cname in @valid_cnames, do: :ok

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

  defp validate_typesize(ts) when is_integer(ts) and ts > 0 and ts <= 256, do: :ok

  defp validate_typesize(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options,
         message: "typesize must be a positive integer up to 256"
       )}

  defp cname_to_int(:blosclz), do: 0
  defp cname_to_int(:lz4), do: 1
  defp cname_to_int(:lz4hc), do: 2
  defp cname_to_int(:snappy), do: 3
  defp cname_to_int(:zlib), do: 4
  defp cname_to_int(:zstd), do: 5

  defp shuffle_to_int(:none), do: 0
  defp shuffle_to_int(:byte), do: 1
  defp shuffle_to_int(:bit), do: 2
end
