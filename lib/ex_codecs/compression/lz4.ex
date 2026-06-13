defmodule ExCodecs.Compression.Lz4 do
  @moduledoc """
  LZ4 compression codec.

  LZ4 is an extremely fast compression algorithm focused on speed.
  It provides compression at over 1 GB/s per core and decompression
  at multi-GB/s speeds.

  LZ4 does not accept configuration options. It uses a fixed compression
  strategy optimized for speed.

  ## Performance Characteristics

    * Extremely fast compression and decompression
    * Lower compression ratio compared to Zstd or Bzip2
    * Ideal for real-time and latency-sensitive applications

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:lz4, "hello world")
      iex> {:ok, decompressed} = ExCodecs.decode(:lz4, compressed)
      iex> decompressed
      "hello world"
  """

  @behaviour ExCodecs.Codec

  @doc """
  Returns codec metadata for the registry.
  """
  def __codec_info__ do
    %ExCodecs.Codec{
      name: :lz4,
      category: :compression,
      module: __MODULE__,
      native?: true,
      streaming?: false,
      configurable?: false,
      version: lz4_version()
    }
  end

  defp lz4_version, do: "1.10.x"

  @doc """
  Encodes (compresses) data using LZ4.

  LZ4 does not accept configuration options.
  """
  @impl true
  def encode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.wrap(:lz4, ExCodecs.Native.lz4_compress(data))
  end

  @doc """
  Decodes (decompresses) LZ4-compressed data.
  """
  @impl true
  def decode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.wrap(:lz4, ExCodecs.Native.lz4_decompress(data))
  end
end
