defmodule ExCodecs do
  @moduledoc """
  A production-quality, extensible BEAM-native codec framework for Elixir.

  ExCodecs provides a unified API for compression, decompression, hashing,
  checksums, binary encodings, and future content-addressing codecs.

  ## Quick Start

      # Compression
      {:ok, compressed} = ExCodecs.encode(:zstd, my_binary)
      {:ok, original} = ExCodecs.decode(:zstd, compressed)

      # With options
      {:ok, compressed} = ExCodecs.encode(:zstd, my_binary, level: 3)
      {:ok, compressed} = ExCodecs.encode(:blosc2, my_binary, cname: :zstd, clevel: 5, shuffle: :byte)

      # Discovery
      ExCodecs.available_codecs()   #=> [:bzip2, :blosc2, :lz4, :snappy, :zstd]
      ExCodecs.supports?(:zstd)     #=> true
      ExCodecs.codec_info(:zstd)    #=> {:ok, %ExCodecs.Codec{...}}

  ## Supported Codecs

  | Codec    | Category    | Description                          |
  |----------|-------------|--------------------------------------|
  | `:zstd`  | compression | Zstandard - high ratio, good speed   |
  | `:lz4`   | compression | LZ4 - extremely fast                 |
  | `:snappy`| compression | Snappy - fast, low overhead          |
  | `:bzip2` | compression | Bzip2 - high ratio, slower           |
  | `:blosc2`| compression | Blosc2 - meta-compressor for arrays  |

  ## Design Philosophy

  ExCodecs is not a compression library. It is a codec framework.
  Compression is merely the first codec category. The architecture
  supports future expansion into hashing, checksums, binary encodings,
  content addressing, and streaming — without changing the public API.
  """

  alias ExCodecs.{Codec, CodecRegistry, Error}

  @doc """
  Encodes data using the specified codec.

  For compression codecs, this compresses the data. For other codec
  categories, the semantics depend on the codec type.

  ## Arguments

    * `codec` - The codec atom (e.g., `:zstd`, `:lz4`)
    * `data` - The binary data to encode
    * `opts` - Codec-specific options (default: `[]`)

  ## Returns

    * `{:ok, encoded_binary}` - Successfully encoded data
    * `{:error, %ExCodecs.Error{}}` - Encoding failed

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:zstd, "hello world")
      iex> is_binary(compressed)
      true

      iex> {:ok, compressed} = ExCodecs.encode(:zstd, "hello world", level: 3)
      iex> is_binary(compressed)
      true

      iex> ExCodecs.encode(:unknown_codec, "data")
      {:error, %ExCodecs.Error{reason: :unsupported_codec}}
  """
  @spec encode(atom(), binary(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(codec, data, opts \\ [])

  def encode(codec, data, opts) when is_atom(codec) and is_binary(data) and is_list(opts) do
    case CodecRegistry.lookup(codec) do
      {:ok, {module, _category, info}} ->
        case ensure_available(info, codec) do
          :ok -> module.encode(data, opts)
          {:error, %Error{} = error} -> {:error, error}
        end

      {:error, :unsupported_codec} ->
        {:error, Error.new(:unsupported_codec, codec: codec)}
    end
  end

  def encode(_codec, _data, _opts) do
    {:error, Error.new(:invalid_data, message: "Data must be a binary")}
  end

  @doc """
  Decodes data using the specified codec.

  For compression codecs, this decompresses the data.

  ## Arguments

    * `codec` - The codec atom (e.g., `:zstd`, `:lz4`)
    * `data` - The binary data to decode
    * `opts` - Codec-specific options (default: `[]`)

  ## Returns

    * `{:ok, decoded_binary}` - Successfully decoded data
    * `{:error, %ExCodecs.Error{}}` - Decoding failed

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:zstd, "hello world")
      iex> {:ok, original} = ExCodecs.decode(:zstd, compressed)
      iex> original
      "hello world"
  """
  @spec decode(atom(), binary(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def decode(codec, data, opts \\ [])

  def decode(codec, data, opts) when is_atom(codec) and is_binary(data) and is_list(opts) do
    case CodecRegistry.lookup(codec) do
      {:ok, {module, _category, info}} ->
        case ensure_available(info, codec) do
          :ok -> module.decode(data, opts)
          {:error, %Error{} = error} -> {:error, error}
        end

      {:error, :unsupported_codec} ->
        {:error, Error.new(:unsupported_codec, codec: codec)}
    end
  end

  def decode(_codec, _data, _opts) do
    {:error, Error.new(:invalid_data, message: "Data must be a binary")}
  end

  @doc """
  Returns a list of all available codec names.

  Only codecs that are loadable and functional are included.

  ## Examples

      iex> ExCodecs.available_codecs()
      [:bzip2, :blosc2, :lz4, :snappy, :zstd]
  """
  @spec available_codecs() :: [atom()]
  def available_codecs do
    CodecRegistry.available_codecs()
  end

  @doc """
  Checks if a codec is supported and available at runtime.

  Returns `true` only if the codec is both registered and its
  native implementation is loaded.

  ## Examples

      iex> ExCodecs.supports?(:zstd)
      true

      iex> ExCodecs.supports?(:nonexistent)
      false
  """
  @spec supports?(atom()) :: boolean()
  def supports?(codec) when is_atom(codec) do
    CodecRegistry.supports?(codec)
  end

  @doc """
  Returns detailed information about a codec.

  ## Returns

    * `{:ok, %ExCodecs.Codec{}}` - Codec information
    * `{:error, :unsupported_codec}` - Codec not found

  ## Examples

      iex> {:ok, info} = ExCodecs.codec_info(:zstd)
      iex> info.name
      :zstd

      iex> info.category
      :compression
  """
  @spec codec_info(atom()) :: {:ok, Codec.t()} | {:error, :unsupported_codec}
  def codec_info(codec) when is_atom(codec) do
    CodecRegistry.codec_info(codec)
  end

  defp ensure_available(info, codec) do
    if info.module != nil do
      :ok
    else
      {:error, Error.new(:codec_unavailable, codec: codec)}
    end
  end
end
