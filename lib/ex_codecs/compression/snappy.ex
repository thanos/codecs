defmodule ExCodecs.Compression.Snappy do
  @moduledoc """
  Standalone Snappy compression codec.

  This is the **registry codec** `:snappy`. It is independent of Blosc2.
  Do not confuse with `ExCodecs.encode(:blosc2, data, cname: :snappy)`, which
  is rejected (Snappy is not a standard C-Blosc2 inner compressor here).

  ## Options

    * `:max_output_size` — Maximum allowed decompressed size in bytes
      (default: 256 MiB).

  ## Security

  Do not decompress untrusted inputs without a tight `:max_output_size`.

  ## Examples

      iex> {:ok, compressed} = ExCodecs.encode(:snappy, "hello world")
      iex> {:ok, decompressed} = ExCodecs.decode(:snappy, compressed)
      iex> decompressed
      "hello world"
  """

  @behaviour ExCodecs.Codec

  @doc """
  Returns the registry metadata for the standalone Snappy codec.

  ## Arguments

  This function takes no arguments.

  ## Returns

  An `ExCodecs.Codec.t()` with these Snappy-specific fields:

    * `name: :snappy` and `category: :compression`
    * `module: ExCodecs.Compression.Snappy`
    * `native?: true` because compression runs in a NIF
    * `streaming?: false` because only complete buffers are supported
    * `configurable?: false` because this codec has no options
    * `version: "snap-1.1"` for the backend implementation

  ## Raises / Exceptions

  This function does not invoke the NIF and does not raise.

  ## Examples

      iex> ExCodecs.Compression.Snappy.__codec_info__()
      %ExCodecs.Codec{
        name: :snappy,
        category: :compression,
        module: ExCodecs.Compression.Snappy,
        native?: true,
        streaming?: false,
        configurable?: false,
        version: "snap-1.1"
      }
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

  defp snappy_version, do: "snap-1.1"

  @doc """
  Compresses a binary with Snappy.

  ## Arguments

    * `data` (`binary()`) — uncompressed bytes
    * `opts` (`term()`) — ignored by this direct function; callers using the
      codec behaviour or registry API should pass the keyword list `[]`

  ## Returns

    * `{:ok, compressed :: binary()}` containing a standalone Snappy block
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :compression_failed}}` when the native
      compressor fails
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Data guard failures and `ErlangError`/`ArgumentError` exceptions from the NIF
  call are converted to error tuples. Because `opts` is ignored, this direct
  function also accepts non-list option terms. Unexpected exception classes
  may propagate.

  ## Examples

      iex> payload = :binary.copy("event,", 25)
      iex> {:ok, compressed} = ExCodecs.Compression.Snappy.encode(payload, [])
      iex> is_binary(compressed)
      true
      iex> ExCodecs.Compression.Snappy.decode(compressed, [])
      {:ok, payload}
  """
  @impl true
  def encode(data, _opts) when is_binary(data) do
    ExCodecs.NIF.safe_call(:snappy, fn -> ExCodecs.Native.snappy_compress(data) end)
  end

  def encode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :snappy)}

  @doc """
  Decompresses Snappy data.

  ## Arguments

    * `data` (`binary()`) — a standalone Snappy block, normally produced by
      `encode/2`
    * `opts` (`term()`) — ignored by this direct function; callers using the
      codec behaviour or registry API should pass the keyword list `[]`

  ## Returns

    * `{:ok, decompressed :: binary()}` on success
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :decompression_failed}}` when `data`
      is corrupt, truncated, or not a Snappy block
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Data guard failures and `ErlangError`/`ArgumentError` exceptions from the NIF
  call are converted to error tuples. Because `opts` is ignored, this direct
  function also accepts non-list option terms. Unexpected exception classes
  may propagate.

  ## Examples

      iex> payload = <<10, 20, 30, 40>>
      iex> {:ok, compressed} = ExCodecs.Compression.Snappy.encode(payload, [])
      iex> ExCodecs.Compression.Snappy.decode(compressed, [])
      {:ok, <<10, 20, 30, 40>>}

      iex> {:error, error} = ExCodecs.Compression.Snappy.decode("not snappy", [])
      iex> error.reason
      :decompression_failed
  """
  @impl true
  def decode(data, opts) when is_binary(data) and is_list(opts) do
    with {:ok, max} <- ExCodecs.NIF.max_output_size(opts) do
      ExCodecs.NIF.safe_call(:snappy, fn -> ExCodecs.Native.snappy_decompress(data, max) end)
    end
  end

  def decode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :snappy)}
end
