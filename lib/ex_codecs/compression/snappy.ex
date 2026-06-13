defmodule ExCodecs.Compression.Snappy do
  @moduledoc """
  Snappy compression codec.

  Snappy (formerly Zippy) is a fast compression algorithm developed by Google.
  It prioritizes speed over compression ratio, achieving compression speeds
  of over 500 MB/s and decompression speeds over 1.5 GB/s.

  Snappy does not accept configuration options. It uses a fixed compression
  strategy optimized for speed.

  ## Performance Characteristics

    * Very fast compression and decompression
    * Lower compression ratio than Zstd or Bzip2
    * Minimal overhead — ideal for short-lived data
    * Deterministic output for identical inputs

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:snappy, "hello world")
      iex> {:ok, decompressed} = ExCodecs.decode(:snappy, compressed)
      iex> decompressed
      "hello world"
  """

  @behaviour ExCodecs.Codec

  @doc """
  Returns codec metadata for the registry.
  """
  def __codec_info__ do
    %ExCodecs.Codec{
      name: :snappy,
      category: :compression,
      module: __MODULE__,
      native?: true,
      streaming?: false,
      configurable?: false,
      version: snappy_version()
    }
  end

  defp snappy_version do
    case ExCodecs.Native.codec_versions() do
      %{:snappy => v} -> v
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  @doc """
  Encodes (compresses) data using Snappy.

  Snappy does not accept configuration options.
  """
  @impl true
  def encode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.wrap(:snappy, ExCodecs.Native.snappy_compress(data))
  end

  @doc """
  Decodes (decompresses) Snappy-compressed data.
  """
  @impl true
  def decode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.wrap(:snappy, ExCodecs.Native.snappy_decompress(data))
  end
end
