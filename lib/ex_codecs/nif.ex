defmodule ExCodecs.NIF do
  @moduledoc false

  @doc """
  Wraps raw NIF error tuples into ExCodecs.Error structs.

  NIF functions return `{:error, atom}` tuples. This helper converts
  them into `{:error, %ExCodecs.Error{}}` tuples for consistent error handling.
  """
  @spec wrap(atom(), {:ok, binary()} | {:error, atom()}) ::
          {:ok, binary()} | {:error, ExCodecs.Error.t()}
  def wrap(_codec, {:ok, data}), do: {:ok, data}

  def wrap(codec, {:error, :compression_failed}),
    do: {:error, ExCodecs.Error.new(:compression_failed, codec: codec)}

  def wrap(codec, {:error, :decompression_failed}),
    do: {:error, ExCodecs.Error.new(:decompression_failed, codec: codec)}

  def wrap(codec, {:error, :invalid_data}),
    do: {:error, ExCodecs.Error.new(:invalid_data, codec: codec)}

  def wrap(codec, {:error, :invalid_options}),
    do: {:error, ExCodecs.Error.new(:invalid_options, codec: codec)}

  def wrap(codec, {:error, reason}), do: {:error, ExCodecs.Error.new(reason, codec: codec)}
end
