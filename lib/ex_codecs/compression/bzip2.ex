defmodule ExCodecs.Compression.Bzip2 do
  @moduledoc """
  Bzip2 compression codec.

  Bzip2 is a high-ratio compression algorithm using the Burrows-Wheeler
  block-sorting text compression algorithm and Huffman coding. It produces
  smaller output than most other algorithms but is significantly slower.

  ## Options

    * `:block_size` — Block size multiplier, 1-9 (default: 9). Higher values
      produce smaller output but use more memory.

  ## Performance Characteristics

    * Excellent compression ratio
    * Slower compression and decompression than Zstd
    * Higher memory usage, especially at higher block sizes
    * Best for archival or storage where ratio matters more than speed

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:bzip2, "hello world")
      iex> {:ok, decompressed} = ExCodecs.decode(:bzip2, compressed)
      iex> decompressed
      "hello world"

      iex> {:ok, compressed} = ExCodecs.encode(:bzip2, "hello world", block_size: 6)
      iex> is_binary(compressed)
      true
  """

  @behaviour ExCodecs.Codec

  @default_block_size 9

  @doc """
  Returns codec metadata for the registry.
  """
  def __codec_info__ do
    %ExCodecs.Codec{
      name: :bzip2,
      category: :compression,
      module: __MODULE__,
      native?: true,
      streaming?: false,
      configurable?: true,
      version: bzip2_version()
    }
  end

  defp bzip2_version, do: "0.4.x"

  @doc """
  Encodes (compresses) data using Bzip2.

  ## Options

    * `:block_size` — Block size 1-9 (default: 9)
  """
  @impl true
  def encode(data, opts) when is_binary(data) and is_list(opts) do
    block_size = Keyword.get(opts, :block_size, @default_block_size)

    with :ok <- validate_block_size(block_size) do
      ExCodecs.NIF.wrap(:bzip2, ExCodecs.Native.bzip2_compress(data, block_size))
    end
  end

  @doc """
  Decodes (decompresses) Bzip2-compressed data.
  """
  @impl true
  def decode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.wrap(:bzip2, ExCodecs.Native.bzip2_decompress(data))
  end

  defp validate_block_size(bs) when is_integer(bs) and bs >= 1 and bs <= 9, do: :ok

  defp validate_block_size(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options,
         message: "Block size must be an integer between 1 and 9"
       )}
end
