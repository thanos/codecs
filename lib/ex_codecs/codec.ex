defmodule ExCodecs.Codec do
  @moduledoc """
  Behaviour and metadata struct for **registry** binary codecs.

  Every module registered with `ExCodecs.CodecRegistry` should implement
  `encode/2` and `decode/2` on **binaries**. Spatial format codecs do **not**
  use this behaviour (they live under `ExCodecs.Spatial`).

  The `%ExCodecs.Codec{}` struct describes a registry entry. Its fields are:

    * `name` (`atom()`) — registry key, such as `:zstd`
    * `category` (`atom()`) — codec category, currently `:compression`
    * `module` (`module() | nil`) — implementation module, or `nil` when the
      codec is known but unavailable
    * `native?` (`boolean()`) — whether the implementation uses a NIF
    * `streaming?` (`boolean()`) — whether an incremental API is available
    * `configurable?` (`boolean()`) — whether the codec accepts meaningful options
    * `version` (`String.t() | nil`) — backend version, if reported

  For example:

      iex> {:ok, %ExCodecs.Codec{} = codec} = ExCodecs.codec_info(:zstd)
      iex> {codec.name, codec.category, codec.module}
      {:zstd, :compression, ExCodecs.Compression.Zstd}

  ## Implementing a codec

      defmodule ExCodecs.Compression.Zstd do
        @behaviour ExCodecs.Codec

        @impl true
        def encode(data, opts) when is_binary(data) and is_list(opts) do
          # ...
        end

        @impl true
        def decode(data, opts) when is_binary(data) and is_list(opts) do
          # ...
        end

        def __codec_info__ do
          %ExCodecs.Codec{
            name: :zstd,
            category: :compression,
            module: __MODULE__,
            native?: true,
            streaming?: false,
            configurable?: true,
            version: "ruzstd-0.8"
          }
        end
      end
  """

  @typedoc """
  Result returned by `c:encode/2`.

  `{:ok, encoded}` contains the encoded binary. `{:error, error}` contains an
  `ExCodecs.Error` whose reason is normally `:invalid_data`, `:invalid_options`,
  `:compression_failed`, or `:nif_not_loaded`.

  ## Example

      iex> {:ok, result} = ExCodecs.Compression.Zstd.encode("codec input", [])
      iex> is_binary(result)
      true
  """
  @type encode_result :: {:ok, binary()} | {:error, ExCodecs.Error.t()}

  @typedoc """
  Result returned by `c:decode/2`.

  `{:ok, decoded}` contains the decoded binary. `{:error, error}` contains an
  `ExCodecs.Error` whose reason is normally `:invalid_data`,
  `:invalid_options`, `:decompression_failed`, `:truncated_input`, or
  `:nif_not_loaded`.

  ## Example

      iex> {:ok, encoded} = ExCodecs.Compression.Zstd.encode("codec input", [])
      iex> ExCodecs.Compression.Zstd.decode(encoded, [])
      {:ok, "codec input"}
  """
  @type decode_result :: {:ok, binary()} | {:error, ExCodecs.Error.t()}

  @doc """
  Encodes binary data (compress, hash, etc.).

  ## Arguments

    * `data` (`binary()`) — bytes to encode
    * `opts` (`keyword()`) — codec-specific options; implementations should
      validate every supported key and value

  ## Returns

    * `{:ok, binary()}` — encoded bytes
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` — invalid input
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` — unsupported or
      invalid options
    * `{:error, %ExCodecs.Error{reason: :compression_failed}}` — backend
      encoding failure
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` — native library
      unavailable

  ## Raises

  Implementations must return an error tuple for invalid data, invalid options,
  and expected backend failures. They may raise only for programmer errors or
  unexpected runtime faults not represented by `ExCodecs.Error`.

  ## Implementation example

      defmodule Example.ReverseCodec do
        @behaviour ExCodecs.Codec

        @impl true
        def encode(data, opts) when is_binary(data) and opts == [] do
          {:ok, String.reverse(data)}
        end

        def encode(data, _opts) when not is_binary(data) do
          ExCodecs.Error.error(:invalid_data, codec: :reverse)
        end

        def encode(_data, _opts) do
          ExCodecs.Error.error(:invalid_options, codec: :reverse)
        end

        @impl true
        def decode(data, opts), do: encode(data, opts)
      end
  """
  @callback encode(data :: binary(), opts :: keyword()) :: encode_result()

  @doc """
  Decodes binary data (decompress, etc.).

  ## Arguments

    * `data` (`binary()`) — encoded bytes to decode
    * `opts` (`keyword()`) — codec-specific decoding options

  ## Returns

    * `{:ok, binary()}` — decoded bytes
    * `{:error, %ExCodecs.Error{reason: :invalid_data}}` — input has the wrong
      type or shape
    * `{:error, %ExCodecs.Error{reason: :invalid_options}}` — unsupported or
      invalid options
    * `{:error, %ExCodecs.Error{reason: :decompression_failed}}` — malformed
      payload or backend decoding failure
    * `{:error, %ExCodecs.Error{reason: :truncated_input}}` — incomplete input,
      when the implementation distinguishes it
    * `{:error, %ExCodecs.Error{reason: :nif_not_loaded}}` — native library
      unavailable

  ## Raises

  Implementations must return an error tuple for malformed data, invalid
  options, and expected backend failures. They may raise only for programmer
  errors or unexpected runtime faults not represented by `ExCodecs.Error`.

  ## Implementation example

      defmodule Example.PrefixCodec do
        @behaviour ExCodecs.Codec

        @impl true
        def encode(data, []) when is_binary(data), do: {:ok, <<"EX", data::binary>>}

        def encode(data, _opts) when not is_binary(data) do
          ExCodecs.Error.error(:invalid_data, codec: :prefix)
        end

        def encode(_data, _opts) do
          ExCodecs.Error.error(:invalid_options, codec: :prefix)
        end

        @impl true
        def decode(<<"EX", data::binary>>, []), do: {:ok, data}

        def decode(data, _opts) when not is_binary(data) do
          ExCodecs.Error.error(:invalid_data, codec: :prefix)
        end

        def decode(_data, []), do: ExCodecs.Error.error(:decompression_failed, codec: :prefix)
        def decode(_data, _opts), do: ExCodecs.Error.error(:invalid_options, codec: :prefix)
      end
  """
  @callback decode(data :: binary(), opts :: keyword()) :: decode_result()

  @typedoc """
  Metadata for one binary codec registry entry.

  Every field is public:

    * `name` — registry atom passed to `ExCodecs.encode/3` and
      `ExCodecs.decode/3`
    * `category` — grouping atom used by
      `ExCodecs.CodecRegistry.codecs_by_category/1`
    * `module` — callback implementation, or `nil` for an unavailable codec
    * `native?` — indicates NIF-backed operation
    * `streaming?` — indicates incremental processing support
    * `configurable?` — indicates codec-specific option support
    * `version` — backend version string, or `nil` if unknown

  ## Example

      iex> {:ok, codec} = ExCodecs.codec_info(:zstd)
      iex> %ExCodecs.Codec{name: :zstd, configurable?: configurable?} = codec
      iex> is_boolean(configurable?)
      true
  """
  @type t :: %__MODULE__{
          name: atom(),
          category: atom(),
          module: module() | nil,
          native?: boolean(),
          streaming?: boolean(),
          configurable?: boolean(),
          version: String.t() | nil
        }

  defstruct [:name, :category, :module, :native?, :streaming?, :configurable?, :version]

  @doc """
  Returns whether `module` exports `encode/2` and `decode/2`.

  ## Arguments

    * `module` (`module()`) — module to load and inspect

  ## Returns

    * `true` — `module` loads and exports both `encode/2` and `decode/2`
    * `false` — it cannot be loaded or either callback is missing

  ## Raises

  Does not raise for a valid `module()` atom. Passing a value outside the
  declared type may raise `FunctionClauseError` from the code-loading API.

  ## Examples

      iex> ExCodecs.Codec.validates?(ExCodecs.Compression.Zstd)
      true

      iex> ExCodecs.Codec.validates?(Nonexistent.Module)
      false
  """
  @spec validates?(module()) :: boolean()
  def validates?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :encode, 2) and
      function_exported?(module, :decode, 2)
  end
end
