defmodule ExCodecs.Compression.Lz4 do
  @moduledoc """
  LZ4 compression codec.

  LZ4 is an extremely fast compression algorithm focused on speed.
  It provides compression at over 1 GB/s per core and decompression
  at multi-GB/s speeds.

  ## Options

    * `:level` — Compression level, 1-16 (default: 1). Higher levels produce
      smaller output but sacrifice speed.

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

  @default_level 1

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
      configurable?: true,
      version: lz4_version()
    }
  end

  defp lz4_version do
    case ExCodecs.Native.codec_versions() do
      %{:lz4 => v} -> v
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  @doc """
  Encodes (compresses) data using LZ4.

  ## Options

    * `:level` — Compression level 1-16 (default: 1)
  """
  @impl true
  def encode(data, opts) when is_binary(data) and is_list(opts) do
    level = Keyword.get(opts, :level, @default_level)

    with :ok <- validate_level(level) do
      ExCodecs.NIF.wrap(:lz4, ExCodecs.Native.lz4_compress(data, level))
    end
  end

  @doc """
  Decodes (decompresses) LZ4-compressed data.
  """
  @impl true
  def decode(data, opts) when is_binary(data) and is_list(opts) do
    ExCodecs.NIF.wrap(:lz4, ExCodecs.Native.lz4_decompress(data))
  end

  defp validate_level(level) when is_integer(level) and level >= 1 and level <= 16, do: :ok

  defp validate_level(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options, message: "Level must be an integer between 1 and 16")}
end
