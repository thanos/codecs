defmodule ExCodecs.Error do
  @moduledoc """
  Standardized error types for ExCodecs.

  All ExCodecs functions return `{:ok, result}` or `{:error, reason}` tuples.
  The `reason` will be one of the atoms defined in this module, or a structured
  error when additional context is needed.
  """

  @type error_reason ::
          :unsupported_codec
          | :codec_unavailable
          | :invalid_data
          | :invalid_options
          | :compression_failed
          | :decompression_failed
          | :nif_not_loaded

  @type t :: %__MODULE__{
          reason: error_reason(),
          message: String.t(),
          codec: atom() | nil,
          details: term() | nil
        }

  defexception [:reason, :message, :codec, :details]

  @doc """
  Creates a new error struct.
  """
  @spec new(error_reason(), keyword()) :: t()
  def new(reason, opts \\ []) do
    %__MODULE__{
      reason: reason,
      message: Keyword.get(opts, :message, default_message(reason)),
      codec: Keyword.get(opts, :codec),
      details: Keyword.get(opts, :details)
    }
  end

  @doc """
  Creates an `{:error, ExCodecs.Error.t()}` tuple.
  """
  @spec error(error_reason(), keyword()) :: {:error, t()}
  def error(reason, opts \\ []) do
    {:error, new(reason, opts)}
  end

  @doc """
  Wraps a raw error tuple into an `{:error, ExCodecs.Error.t()}`.
  """
  @spec from_nif({:error, term()}, atom()) :: {:error, t()}
  def from_nif({:error, reason}, codec) when is_atom(codec) do
    {:error,
     %__MODULE__{
       reason: nif_error_to_atom(reason),
       message: "NIF error in codec #{codec}: #{inspect(reason)}",
       codec: codec,
       details: reason
     }}
  end

  defp default_message(:unsupported_codec), do: "The specified codec is not supported"
  defp default_message(:codec_unavailable), do: "The codec is known but not available at runtime"
  defp default_message(:invalid_data), do: "The input data is invalid for this codec"
  defp default_message(:invalid_options), do: "The provided options are invalid"
  defp default_message(:compression_failed), do: "Compression failed"
  defp default_message(:decompression_failed), do: "Decompression failed"
  defp default_message(:nif_not_loaded), do: "The native NIF library is not loaded"

  defp nif_error_to_atom(reason) when is_atom(reason), do: reason
  defp nif_error_to_atom(_), do: :compression_failed

  @impl true
  def message(%__MODULE__{message: message}), do: message

  @doc """
  Checks if an error matches a specific reason.
  """
  @spec matches?({:error, t()}, error_reason()) :: boolean()
  def matches?({:error, %__MODULE__{reason: reason}}, reason), do: true
  def matches?(_, _), do: false
end
