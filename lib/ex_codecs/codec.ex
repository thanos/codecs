defmodule ExCodecs.Codec do
  @moduledoc """
  Binary-codec behaviour and shared catalog metadata.

  Binary-interface modules registered with `ExCodecs.CodecRegistry` implement
  this module's `encode/2` and `decode/2` callbacks on **binaries**. Spatial
  entries share the catalog metadata struct but use the specialized
  `ExCodecs.Spatial` contract because they map domain structs↔formats.

  The `%ExCodecs.Codec{}` struct describes any shared-catalog entry. Its fields
  are:

    * `name` (`atom()`) — registry key, such as `:zstd`
    * `category` (`atom()`) — codec category, such as `:compression` or `:spatial`
    * `interface` (`:binary | :spatial`) — public API shape used by the entry
    * `module` (`module() | nil`) — implementation module, or `nil` when the
      codec is known but unavailable
    * `native?` (`boolean() | nil`) — whether the implementation uses a NIF
    * `streaming?` (`boolean() | nil`) — whether an incremental API is available
    * `configurable?` (`boolean() | nil`) — whether the codec accepts meaningful options
    * `version` (`String.t() | nil`) — backend version, if reported

  Boolean capability fields and `version` may be `nil` on a bare `%ExCodecs.Codec{}`
  until filled by `c:__codec_info__/0` and/or `ExCodecs.CodecRegistry.register/5`.

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

        @impl true
        def __codec_info__ do
          %ExCodecs.Codec{
            name: :zstd,
            category: :compression,
            module: __MODULE__,
            native?: true,
            streaming?: false,
            configurable?: true,
            version: "structured-zstd-0.0.48"
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

  Requires the NIF to be loaded (Zstd is NIF-backed). On a host without the
  NIF, use a pure-Elixir codec or `ExCodecs.supports?(:zstd)` to gate.

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

  Requires the NIF to be loaded.

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

  @doc """
  Returns catalog metadata for this codec module.

  Optional. When exported, `ExCodecs.CodecRegistry.register/5` reads capability
  fields (`native?`, `streaming?`, `configurable?`, `version`) from the returned
  struct unless the caller overrides them via the `metadata` keyword. Registry
  arguments always supply `name`, `category`, `interface`, and `module` on the
  stored entry.

  ## Arguments

  None.

  ## Returns

  An `%ExCodecs.Codec{}` whose capability fields describe this implementation.
  Callers may leave `name`/`category`/`interface` unset when the registry fills
  those from `register/5` arguments.

  ## Raises

  Implementations should not raise for a normal metadata return. Any exception
  raised here propagates through registration.

  ## Implementation example

      defmodule ExCodecs.Compression.Zstd do
        @behaviour ExCodecs.Codec

        @impl true
        def __codec_info__ do
          %ExCodecs.Codec{
            name: :zstd,
            category: :compression,
            module: __MODULE__,
            native?: true,
            streaming?: false,
            configurable?: true,
            version: "structured-zstd-0.0.48"
          }
        end
      end
  """
  @callback __codec_info__() :: t()

  @optional_callbacks __codec_info__: 0

  @typedoc """
  Metadata for one shared codec-catalog entry.

  Every field is public:

    * `name` — catalog atom; binary entries can be passed to
      `ExCodecs.encode/3` and `ExCodecs.decode/3`
    * `category` — grouping atom used by
      `ExCodecs.CodecRegistry.codecs_by_category/1`
    * `interface` — `:binary` for the top-level registry API or `:spatial` for
      `ExCodecs.Spatial`
    * `module` — callback implementation, or `nil` for an unavailable codec
    * `native?` — indicates NIF-backed operation, or `nil` until known
    * `streaming?` — indicates incremental processing support, or `nil` until known
    * `configurable?` — indicates codec-specific option support, or `nil` until known
    * `version` — backend version string, or `nil` if unknown

  Boolean capability fields default to `nil` on `%ExCodecs.Codec{}` and are
  typically filled by `c:__codec_info__/0` and/or registry registration. After
  a successful `register/5` or `register_unavailable/3` they are usually
  concrete booleans; `nil` means unknown / not yet filled.

  ## Example

      iex> {:ok, codec} = ExCodecs.codec_info(:zstd)
      iex> %ExCodecs.Codec{name: :zstd, configurable?: configurable?} = codec
      iex> is_boolean(configurable?)
      true
  """
  @type t :: %__MODULE__{
          name: atom(),
          category: atom(),
          interface: :binary | :spatial,
          module: module() | nil,
          native?: boolean() | nil,
          streaming?: boolean() | nil,
          configurable?: boolean() | nil,
          version: String.t() | nil
        }

  defstruct name: nil,
            category: nil,
            interface: :binary,
            module: nil,
            native?: nil,
            streaming?: nil,
            configurable?: nil,
            version: nil

  @doc """
  Returns whether `module` exports `encode/2` and `decode/2`.

  Despite the name, this checks **interface conformance** (the module
  implements the codec callbacks), not runtime data validation.

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
