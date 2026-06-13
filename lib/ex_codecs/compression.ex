defmodule ExCodecs.Compression do
  @moduledoc """
  Compression codec category for ExCodecs.

  This module serves as a namespace for compression codecs and provides
  category-level utilities for comparing and selecting compression algorithms.

  ## Available Codecs

    * `ExCodecs.Compression.Zstd` — High ratio, good speed
    * `ExCodecs.Compression.Lz4` — Extremely fast compression
    * `ExCodecs.Compression.Snappy` — Fast with low overhead
    * `ExCodecs.Compression.Bzip2` — High compression ratio
    * `ExCodecs.Compression.Blosc2` — Meta-compressor for array data

  ## Compression vs Encoding

  In ExCodecs, compression is encoding — and decompression is decoding.
  This consistent terminology spans all codec categories:

      # These are equivalent
      ExCodecs.encode(:zstd, data)     # compress
      ExCodecs.decode(:zstd, data)     # decompress
  """

  alias ExCodecs.CodecRegistry

  @doc """
  Returns all available compression codecs.

  Returns a list of `%ExCodecs.Codec{}` structs sorted by name.

  ## Examples

      iex> codecs = ExCodecs.Compression.available_codecs()
      iex> is_list(codecs) and length(codecs) >= 5
      true
  """
  @spec available_codecs() :: [ExCodecs.Codec.t()]
  def available_codecs do
    CodecRegistry.codecs_by_category(:compression)
  end

  @doc """
  Compresses data with the specified codec.

  Shortcut for `ExCodecs.encode/3`.
  """
  @spec compress(atom(), binary(), keyword()) :: {:ok, binary()} | {:error, ExCodecs.Error.t()}
  def compress(codec, data, opts \\ []) do
    ExCodecs.encode(codec, data, opts)
  end

  @doc """
  Decompresses data with the specified codec.

  Shortcut for `ExCodecs.decode/3`.
  """
  @spec decompress(atom(), binary(), keyword()) :: {:ok, binary()} | {:error, ExCodecs.Error.t()}
  def decompress(codec, data, opts \\ []) do
    ExCodecs.decode(codec, data, opts)
  end
end
