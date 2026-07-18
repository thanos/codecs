defmodule ExCodecs.Compression.Bzip2 do
  @moduledoc """
  Bzip2 compression codec (pure-Rust backend).

  ## Options

    * `:block_size` — 1..9 (default 9)
    * `:max_output_size` — Maximum allowed decompressed size in bytes
      (default: 256 MiB)

  ## Security

  Do not decompress untrusted inputs without a tight `:max_output_size`.

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
  Returns the registry metadata for the Bzip2 codec.

  ## Arguments

  This function takes no arguments.

  ## Returns

  An `ExCodecs.Codec.t()` with these Bzip2-specific fields:

    * `name: :bzip2` and `category: :compression`
    * `module: ExCodecs.Compression.Bzip2`
    * `native?: true` because compression runs in a NIF
    * `streaming?: false` because only complete payloads are supported
    * `configurable?: true` because `encode/2` accepts `:block_size`
    * `version: "bzip2-0.6/libbz2-rs"` for the backend implementation

  ## Raises / Exceptions

  This function does not invoke the NIF and does not raise.

  ## Examples

      iex> ExCodecs.Compression.Bzip2.__codec_info__()
      %ExCodecs.Codec{
        name: :bzip2,
        category: :compression,
        module: ExCodecs.Compression.Bzip2,
        native?: true,
        streaming?: false,
        configurable?: true,
        version: "bzip2-0.6/libbz2-rs"
      }
  """
  @impl true
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

  defp bzip2_version, do: "bzip2-0.6/libbz2-rs"

  @doc """
  Compresses a binary with Bzip2.

  ## Arguments

    * `data` (`binary()`) — uncompressed bytes
    * `opts` (`keyword()`) — options containing `:block_size`, an integer from
      `1` (100 KiB blocks) through `9` (900 KiB blocks); defaults to `9`.
      Unknown keys are ignored.

  ## Returns

    * `{:ok, compressed :: binary()}` containing a Bzip2 stream
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, `opts` is not a list, or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` when `:block_size`
      is not an integer in `1..9`
    * `{:error, %ExCodecs.Error{reason: :compression_failed}}` when the native
      compressor fails
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Guard/option validation failures and `ErlangError`/`ArgumentError`
  exceptions from the NIF call are converted to error tuples. Unexpected
  exception classes may propagate.

  ## Examples

      iex> payload = :binary.copy("daily-report,", 10)
      iex> {:ok, compressed} =
      ...>   ExCodecs.Compression.Bzip2.encode(payload, block_size: 6)
      iex> is_binary(compressed)
      true
      iex> ExCodecs.Compression.Bzip2.decode(compressed, [])
      {:ok, payload}

      iex> {:error, error} = ExCodecs.Compression.Bzip2.encode("data", block_size: 10)
      iex> error.reason
      :invalid_options
  """
  @impl true
  def encode(data, opts) when is_binary(data) and is_list(opts) do
    block_size = Keyword.get(opts, :block_size, @default_block_size)

    with :ok <- validate_block_size(block_size) do
      ExCodecs.NIF.safe_call(:bzip2, fn -> ExCodecs.Native.bzip2_compress(data, block_size) end)
    end
  end

  def encode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :bzip2)}

  @doc """
  Decompresses Bzip2 data.

  ## Arguments

    * `data` (`binary()`) — a complete Bzip2 stream
    * `opts` (`keyword()`) — optional `:max_output_size` (positive integer
      bytes, default 256 MiB)

  ## Returns

    * `{:ok, decompressed :: binary()}` on success
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, `opts` is not a list, or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` when
      `:max_output_size` is not a positive integer
    * `{:error, %ExCodecs.Error{reason: :output_limit_exceeded}}` when the
      decompressed size would exceed `:max_output_size`
    * `{:error, %ExCodecs.Error{reason: :decompression_failed}}` when `data`
      is corrupt, truncated, or not a Bzip2 stream
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Guard failures and `ErlangError`/`ArgumentError` exceptions from the NIF
  call are converted to error tuples. Unexpected exception classes may
  propagate.

  ## Examples

      iex> payload = "quarterly results"
      iex> {:ok, compressed} = ExCodecs.Compression.Bzip2.encode(payload, [])
      iex> ExCodecs.Compression.Bzip2.decode(compressed, [])
      {:ok, "quarterly results"}

      iex> {:error, error} = ExCodecs.Compression.Bzip2.decode("not bzip2", [])
      iex> error.reason
      :decompression_failed
  """
  @impl true
  def decode(data, opts) when is_binary(data) and is_list(opts) do
    with {:ok, max} <- ExCodecs.NIF.max_output_size(opts) do
      ExCodecs.NIF.safe_call(:bzip2, fn -> ExCodecs.Native.bzip2_decompress(data, max) end)
    end
  end

  def decode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :bzip2)}

  defp validate_block_size(bs) when is_integer(bs) and bs >= 1 and bs <= 9, do: :ok

  defp validate_block_size(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options,
         message: "Block size must be an integer between 1 and 9"
       )}
end
