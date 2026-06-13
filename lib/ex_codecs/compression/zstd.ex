defmodule ExCodecs.Compression.Zstd do
  @moduledoc """
  Zstandard (Zstd) compression codec.

  Zstd is a fast compression algorithm providing high compression ratios.
  It was developed by Yann Collet at Facebook and offers configurable
  compression levels from 1 (fastest) to 22 (smallest).

  ## Options

    * `:level` — Compression level, 1-22 (default: 3). Higher levels produce
      smaller output but take longer.
    * `:window_log` — Window log size. Controls the maximum reference distance.

  ## Performance Characteristics

    * Fast decompression across all compression levels
    * Compression speed configurable via level
    * Excellent ratio at moderate speeds
    * Supports dictionary compression for small data

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:zstd, "hello world")
      iex> {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      iex> decompressed
      "hello world"

      iex> {:ok, compressed} = ExCodecs.encode(:zstd, "hello world", level: 9)
      iex> is_binary(compressed)
      true
  """

  @behaviour ExCodecs.Codec

  @default_level 3

  @doc """
  Returns codec metadata for the registry.
  """
  def __codec_info__ do
    %ExCodecs.Codec{
      name: :zstd,
      category: :compression,
      module: __MODULE__,
      native?: true,
      streaming?: true,
      configurable?: true,
      version: zstd_version()
    }
  end

  @doc false
  defp zstd_version do
    case ExCodecs.Native.codec_versions() do
      %{:zstd => v} -> v
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  @doc """
  Encodes (compresses) data using Zstd.

  ## Options

    * `:level` — Compression level 1-22 (default: 3)
  """
  @impl true
  def encode(data, opts) when is_binary(data) and is_list(opts) do
    level = Keyword.get(opts, :level, @default_level)

    with :ok <- validate_level(level) do
      ExCodecs.NIF.wrap(:zstd, ExCodecs.Native.zstd_compress(data, level))
    end
  end

  @doc """
  Decodes (decompresses) Zstd-compressed data.

  The decompressed size is read from the frame header.
  """
  @impl true
  def decode(data, opts) when is_binary(data) and is_list(opts) do
    ExCodecs.NIF.wrap(:zstd, ExCodecs.Native.zstd_decompress(data))
  end

  defp validate_level(level) when is_integer(level) and level >= 1 and level <= 22, do: :ok

  defp validate_level(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options, message: "Level must be an integer between 1 and 22")}
end
