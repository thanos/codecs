defmodule ExCodecs.NIF do
  @moduledoc false

  # Default decompress ceiling: 256 MiB. Override with `max_output_size:`.
  @default_max_output_size 268_435_456

  @doc false
  def default_max_output_size, do: @default_max_output_size

  @doc false
  def max_output_size(opts) when is_list(opts) do
    case Keyword.get(opts, :max_output_size, @default_max_output_size) do
      n when is_integer(n) and n > 0 ->
        {:ok, n}

      _ ->
        {:error,
         ExCodecs.Error.new(:invalid_options,
           message: "max_output_size must be a positive integer (bytes)"
         )}
    end
  end

  @doc """
  Wraps raw NIF error tuples into ExCodecs.Error structs.

  NIF functions return `{:error, atom}` tuples. This helper converts
  them into `{:error, %ExCodecs.Error{}}` tuples for consistent error handling.
  """
  @spec wrap(atom(), {:ok, binary()} | {:error, atom()} | term()) ::
          {:ok, binary()} | {:error, ExCodecs.Error.t()}
  def wrap(_codec, {:ok, data}) when is_binary(data), do: {:ok, data}

  def wrap(codec, {:error, :compression_failed}),
    do: {:error, ExCodecs.Error.new(:compression_failed, codec: codec)}

  def wrap(codec, {:error, :decompression_failed}),
    do: {:error, ExCodecs.Error.new(:decompression_failed, codec: codec)}

  def wrap(codec, {:error, :output_limit_exceeded}),
    do:
      {:error,
       ExCodecs.Error.new(:output_limit_exceeded,
         codec: codec,
         message:
           "Decompressed output exceeded max_output_size " <>
             "(default #{@default_max_output_size} bytes). " <>
             "Pass a larger max_output_size: for trusted inputs."
       )}

  def wrap(codec, {:error, :invalid_data}),
    do: {:error, ExCodecs.Error.new(:invalid_data, codec: codec)}

  def wrap(codec, {:error, :invalid_options}),
    do: {:error, ExCodecs.Error.new(:invalid_options, codec: codec)}

  def wrap(codec, {:error, reason}) when is_atom(reason),
    do: {:error, ExCodecs.Error.new(reason, codec: codec)}

  def wrap(codec, other) do
    {:error,
     ExCodecs.Error.new(:invalid_data,
       codec: codec,
       message: "Unexpected NIF return: #{inspect(other)}"
     )}
  end

  @doc """
  Invokes a zero-arity NIF function and wraps ErlangError/`nif_not_loaded`.
  """
  @spec safe_call(atom(), (-> term())) :: {:ok, term()} | {:error, ExCodecs.Error.t()}
  def safe_call(codec, fun) when is_function(fun, 0) do
    wrap(codec, fun.())
  rescue
    e in ErlangError ->
      case e.original do
        :nif_not_loaded ->
          {:error, ExCodecs.Error.new(:nif_not_loaded, codec: codec)}

        other ->
          {:error, ExCodecs.Error.new(:invalid_data, codec: codec, details: other)}
      end

    e in ArgumentError ->
      {:error, ExCodecs.Error.new(:invalid_data, codec: codec, message: Exception.message(e))}
  end
end
