defmodule ExCodecs.Codec do
  @moduledoc """
  Behaviour definition for ExCodecs codecs.

  Every codec implementation must conform to this behaviour, providing
  `encode/2` and `decode/2` callbacks that operate on binaries with
  optional keyword-list configuration.

  ## Implementing a Codec

       defmodule ExCodecs.Compression.Zstd do
         @behaviour ExCodecs.Codec

         @impl true
         def encode(data, opts) do
           level = Keyword.get(opts, :level, 3)
           with :ok <- validate_level(level) do
             ExCodecs.NIF.wrap(:zstd, ExCodecs.Native.zstd_compress(data, level))
           end
         end

         @impl true
         def decode(data, _opts) do
           ExCodecs.NIF.wrap(:zstd, ExCodecs.Native.zstd_decompress(data))
         end
       end

  ## Codec Metadata

  Codec modules should also export a `__codec_info__/0` function
  that returns metadata about the codec for the registry:

       def __codec_info__ do
         %ExCodecs.Codec{
           name: :zstd,
           category: :compression,
           native?: true,
           streaming?: true,
           configurable?: true,
           version: "1.5.x"
         }
       end
  """

  @type encode_result :: {:ok, binary()} | {:error, ExCodecs.Error.t()}
  @type decode_result :: {:ok, binary()} | {:error, ExCodecs.Error.t()}

  @doc """
  Encodes (compresses, hashes, etc.) the given binary data.

  ## Arguments

    * `data` - The binary data to encode
    * `opts` - Codec-specific options as a keyword list

  ## Returns

    * `{:ok, encoded_binary}` - Successfully encoded data
    * `{:error, %ExCodecs.Error{}}` - Encoding failed
  """
  @callback encode(data :: binary(), opts :: keyword()) :: encode_result()

  @doc """
  Decodes (decompresses, etc.) the given binary data.

  ## Arguments

    * `data` - The binary data to decode
    * `opts` - Codec-specific options as a keyword list

  ## Returns

    * `{:ok, decoded_binary}` - Successfully decoded data
    * `{:error, %ExCodecs.Error{}}` - Decoding failed
  """
  @callback decode(data :: binary(), opts :: keyword()) :: decode_result()

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
  Validates that a module implements the ExCodecs.Codec behaviour.
  """
  @spec validates?(module()) :: boolean()
  def validates?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :encode, 2) and
      function_exported?(module, :decode, 2)
  end
end
