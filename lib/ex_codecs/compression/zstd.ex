defmodule ExCodecs.Compression.Zstd do
  @moduledoc """
  Zstandard (Zstd) compression codec.

  Pure-Rust backend via `structured-zstd` (no C libzstd). Compression levels
  `1`–`22` are passed through to the encoder. Ratios and exact bytes may differ
  from reference C Zstd at the same numeric level.

  ## Options

    * `:level` — Compression level, 1-22 (default: 3).
    * `:max_output_size` — Maximum allowed decompressed size in bytes
      (default: 256 MiB). Rejects bombs that would expand beyond the limit.

  ## Security

  Do not decompress **untrusted** inputs without a tight `:max_output_size`.
  A small malicious frame can expand to a large allocation.

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
    * `version: "structured-zstd-0.0.48"` for the backend implementation

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
        version: "structured-zstd-0.0.48"
      }
  """
  @impl true
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

  defp zstd_version do
    case ExCodecs.Native.nif_loaded?() do
      true ->
        versions = ExCodecs.Native.codec_versions()
        Map.get(versions, "zstd", "structured-zstd-0.0.48")

      false ->
        "structured-zstd-0.0.48"
    end
  rescue
    _ -> "structured-zstd-0.0.48"
  end

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

  ## Notes

  The Elixir layer rejects out-of-range `:level` with `:invalid_options`,
  while the Rust NIF silently clamps. Direct `ExCodecs.Native` callers bypass
  this validation.

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
    with {:ok, max} <- ExCodecs.NIF.max_output_size(opts) do
      ExCodecs.NIF.safe_call(:zstd, fn -> ExCodecs.Native.zstd_decompress(data, max) end)
    end
  end

  def decode(_data, _opts), do: {:error, ExCodecs.Error.new(:invalid_data, codec: :zstd)}

  defp validate_level(level) when is_integer(level) and level >= 1 and level <= 22, do: :ok

  defp validate_level(_),
    do:
      {:error,
       ExCodecs.Error.new(:invalid_options, message: "Level must be an integer between 1 and 22")}
end
