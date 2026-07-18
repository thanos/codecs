defmodule ExCodecs.Compression.Lz4 do
  @moduledoc """
  LZ4 compression codec (size-prepended `lz4_flex` blocks).

  Not interchangeable with lz4frame / CLI `.lz4` files unless they use the
  same size-prefix framing.

  ## Options

    * `:max_output_size` — Maximum allowed decompressed size in bytes
      (default: 256 MiB).

  ## Security

  Do not decompress untrusted inputs without a tight `:max_output_size`.

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:lz4, "hello world")
      iex> {:ok, decompressed} = ExCodecs.decode(:lz4, compressed)
      iex> decompressed
      "hello world"
  """

  @behaviour ExCodecs.Codec

  @doc """
  Returns the registry metadata for the LZ4 codec.

  ## Arguments

  This function takes no arguments.

  ## Returns

  An `ExCodecs.Codec.t()` with these LZ4-specific fields:

    * `name: :lz4` and `category: :compression`
    * `module: ExCodecs.Compression.Lz4`
    * `native?: true` because compression runs in a NIF
    * `streaming?: false` because only complete blocks are supported
    * `configurable?: false` because this codec has no options
    * `version: "lz4_flex-0.11"` for the backend implementation

  ## Raises / Exceptions

  This function does not invoke the NIF and does not raise.

  ## Examples

      iex> ExCodecs.Compression.Lz4.__codec_info__()
      %ExCodecs.Codec{
        name: :lz4,
        category: :compression,
        module: ExCodecs.Compression.Lz4,
        native?: true,
        streaming?: false,
        configurable?: false,
        version: "lz4_flex-0.11"
      }
  """
  @impl true
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

  defp lz4_version, do: "lz4_flex-0.11"

  @doc """
  Compresses a binary as a size-prepended `lz4_flex` block.

  ## Arguments

    * `data` (`binary()`) — uncompressed bytes
    * `opts` (`term()`) — ignored by this direct function; callers using the
      codec behaviour or registry API should pass the keyword list `[]`

  ## Returns

    * `{:ok, compressed :: binary()}` containing the uncompressed-size prefix
      and LZ4 block
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, the NIF raises an argument error, or it returns an unexpected
      value
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Argument guard failures and `ErlangError`/`ArgumentError` exceptions from the
  NIF call are converted to error tuples. Unexpected exception classes may
  propagate.

  ## Examples

      iex> payload = "temperature=21.7"
      iex> {:ok, compressed} = ExCodecs.Compression.Lz4.encode(payload, [])
      iex> byte_size(compressed) > 4
      true
      iex> ExCodecs.Compression.Lz4.decode(compressed, [])
      {:ok, "temperature=21.7"}
  """
  @impl true
  def encode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.safe_call(:lz4, fn -> ExCodecs.Native.lz4_compress(data) end)
  end

  def encode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :lz4)}

  @doc """
  Decompresses LZ4 size-prepended data.

  ## Arguments

    * `data` (`binary()`) — a size-prepended `lz4_flex` block, normally
      produced by `encode/2`
    * `opts` (`keyword()`) — optional `:max_output_size` (positive integer
      bytes, default 256 MiB)

  ## Returns

    * `{:ok, decompressed :: binary()}` on success
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, the NIF raises an argument error, or it returns an unexpected
      value
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` when
      `:max_output_size` is not a positive integer
    * `{:error, %ExCodecs.Error{reason: :output_limit_exceeded}}` when the
      claimed or actual size exceeds `:max_output_size`
    * `{:error, %ExCodecs.Error{reason: :decompression_failed}}` when the size
      prefix or compressed block is corrupt, truncated, or incompatible
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Argument guard failures and `ErlangError`/`ArgumentError` exceptions from the
  NIF call are converted to error tuples. Unexpected exception classes may
  propagate.

  ## Examples

      iex> payload = <<1, 2, 3, 4, 5>>
      iex> {:ok, compressed} = ExCodecs.Compression.Lz4.encode(payload, [])
      iex> ExCodecs.Compression.Lz4.decode(compressed, [])
      {:ok, <<1, 2, 3, 4, 5>>}

      iex> {:error, error} = ExCodecs.Compression.Lz4.decode(<<1, 2>>, [])
      iex> error.reason
      :decompression_failed
  """
  @impl true
  def decode(data, opts) when is_binary(data) and is_list(opts) do
    with {:ok, max} <- ExCodecs.NIF.max_output_size(opts) do
      ExCodecs.NIF.safe_call(:lz4, fn -> ExCodecs.Native.lz4_decompress(data, max) end)
    end
  end

  def decode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :lz4)}
end
