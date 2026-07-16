defmodule ExCodecs.Compression.Zstd do
  @moduledoc """
  Zstandard (Zstd) compression codec.

  Zstd is a fast compression algorithm providing high compression ratios.
  It was developed by Yann Collet at Facebook and offers configurable
  compression levels from 1 (fastest) to 22 (smallest).

  ## Options

    * `:level` — Compression level, 1-22 (default: 3). The pure-Rust backend
      (`ruzstd`) currently maps all levels to a fast profile; higher values are
      accepted for API stability and may gain finer control in future releases.

  ## Performance Characteristics

    * Pure-Rust compress/decompress (no C libzstd)
    * Fast decompression
    * Block-level API only (`streaming?` is `false`)

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
  Returns the registry metadata for the Zstandard codec.

  ## Arguments

  This function takes no arguments.

  ## Returns

  An `ExCodecs.Codec.t()` with these Zstd-specific fields:

    * `name: :zstd` and `category: :compression`
    * `module: ExCodecs.Compression.Zstd`
    * `native?: true` because compression runs in a NIF
    * `streaming?: false` because only complete frames are supported
    * `configurable?: true` because `encode/2` accepts `:level`
    * `version: "ruzstd-0.8"` for the backend implementation

  ## Raises / Exceptions

  This function does not invoke the NIF and does not raise.

  ## Examples

      iex> ExCodecs.Compression.Zstd.__codec_info__()
      %ExCodecs.Codec{
        name: :zstd,
        category: :compression,
        module: ExCodecs.Compression.Zstd,
        native?: true,
        streaming?: false,
        configurable?: true,
        version: "ruzstd-0.8"
      }
  """
  def __codec_info__ do
    %ExCodecs.Codec{
      name: :zstd,
      category: :compression,
      module: __MODULE__,
      native?: true,
      streaming?: false,
      configurable?: true,
      version: zstd_version()
    }
  end

  defp zstd_version, do: "ruzstd-0.8"

  @doc """
  Compresses a binary with pure-Rust Zstd.

  ## Arguments

    * `data` (`binary()`) — uncompressed bytes
    * `opts` (`keyword()`) — options containing `:level`, an integer from
      `1` through `22`; the default is `3`. Unknown keys are ignored.

  ## Returns

    * `{:ok, frame :: binary()}` containing a Zstandard frame
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, `opts` is not a list, or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` when `:level` is
      not an integer in `1..22`
    * `{:error, %ExCodecs.Error{reason: :compression_failed}}` when the native
      compressor fails
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Guard/option validation failures and `ErlangError`/`ArgumentError`
  exceptions from the NIF call are converted to error tuples. Unexpected
  exception classes may propagate.

  ## Examples

      iex> payload = :binary.copy("telemetry,", 20)
      iex> {:ok, compressed} = ExCodecs.Compression.Zstd.encode(payload, level: 9)
      iex> is_binary(compressed)
      true
      iex> ExCodecs.Compression.Zstd.decode(compressed, [])
      {:ok, payload}

      iex> {:error, error} = ExCodecs.Compression.Zstd.encode("data", level: 0)
      iex> error.reason
      :invalid_options
  """
  @impl true
  def encode(data, opts) when is_binary(data) and is_list(opts) do
    level = Keyword.get(opts, :level, @default_level)

    with :ok <- validate_level(level) do
      ExCodecs.NIF.safe_call(:zstd, fn -> ExCodecs.Native.zstd_compress(data, level) end)
    end
  end

  def encode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :zstd)}

  @doc """
  Decompresses a Zstd frame binary.

  ## Arguments

    * `data` (`binary()`) — a complete Zstandard frame
    * `opts` (`keyword()`) — currently ignored, but must be a list; pass `[]`

  ## Returns

    * `{:ok, decompressed :: binary()}` on success
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` when `data` is not a
      binary, `opts` is not a list, or the NIF raises an argument error
    * `{:error, %ExCodecs.Error{reason: :decompression_failed}}` when `data`
      is corrupt, truncated, or not a Zstandard frame
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` when the native
      library is unavailable

  ## Raises / Exceptions

  Guard failures and `ErlangError`/`ArgumentError` exceptions from the NIF
  call are converted to error tuples. Unexpected exception classes may
  propagate.

  ## Examples

      iex> payload = <<0, 10, 20, 30, 40>>
      iex> {:ok, compressed} = ExCodecs.Compression.Zstd.encode(payload, [])
      iex> ExCodecs.Compression.Zstd.decode(compressed, [])
      {:ok, <<0, 10, 20, 30, 40>>}

      iex> {:error, error} = ExCodecs.Compression.Zstd.decode("not zstd", [])
      iex> error.reason
      :decompression_failed
  """
  @impl true
  def decode(data, opts) when is_binary(data) and is_list(opts) do
    ExCodecs.NIF.safe_call(:zstd, fn -> ExCodecs.Native.zstd_decompress(data) end)
  end

  def decode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :zstd)}

  defp validate_level(level) when is_integer(level) and level >= 1 and level <= 22, do: :ok

  defp validate_level(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options, message: "Level must be an integer between 1 and 22")}
end
