defmodule ExCodecs.CodecRegistry do
  @moduledoc """
  Runtime codec registry for ExCodecs.

  The registry maintains a mapping of codec names to their implementations
  and metadata. Codecs are registered at application startup and can be
  queried at runtime.

  ## Registry Operations

      iex> ExCodecs.available_codecs()
      [:zstd, :lz4, :snappy, :bzip2, :blosc2]

      iex> ExCodecs.supports?(:zstd)
      true

      iex> ExCodecs.codec_info(:zstd)
      %ExCodecs.Codec{name: :zstd, category: :compression, ...}

  The registry is backed by an ETS table for fast lookups and is
  populated when the application starts.
  """

  use Agent

  @table_name :ex_codecs_registry
  @registry_name __MODULE__

  @doc """
  Starts the registry agent.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> :ets.new(@table_name, [:set, :public, :named_table]) end,
      name: @registry_name
    )
  end

  @doc """
  Registers a codec with the registry.

  ## Arguments

    * `name` - The atom name of the codec (e.g., `:zstd`)
    * `module` - The module implementing `ExCodecs.Codec`
    * `category` - The codec category (e.g., `:compression`)

  ## Returns

    * `:ok` - Codec registered successfully
    * `{:error, reason}` - Registration failed
  """
  @spec register(atom(), module(), atom()) :: :ok | {:error, term()}
  def register(name, module, category) do
    codec_info = build_codec_info(name, module, category)

    case ExCodecs.Codec.validates?(module) do
      true ->
        :ets.insert(@table_name, {name, {module, category, codec_info}})
        :ok

      false ->
        {:error, {:invalid_codec_module, module}}
    end
  end

  @doc """
  Registers a codec as unavailable (known but not loadable).
  """
  @spec register_unavailable(atom(), atom()) :: :ok
  def register_unavailable(name, category) do
    codec_info = %ExCodecs.Codec{
      name: name,
      category: category,
      module: nil,
      native?: false,
      streaming?: false,
      configurable?: false,
      version: nil
    }

    :ets.insert(@table_name, {name, {nil, category, codec_info}})
    :ok
  end

  @doc """
  Looks up a codec by name.

  ## Returns

    * `{:ok, {module, category, info}}` - Codec found
    * `{:error, :unsupported_codec}` - Codec not found
  """
  @spec lookup(atom()) ::
          {:ok, {module(), atom(), ExCodecs.Codec.t()}} | {:error, :unsupported_codec}
  def lookup(name) when is_atom(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, {module, category, info}}] ->
        {:ok, {module, category, info}}

      [] ->
        {:error, :unsupported_codec}
    end
  end

  @doc """
  Returns a list of all available codec names.
  """
  @spec available_codecs() :: [atom()]
  def available_codecs do
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {_name, {module, _category, _info}} -> module != nil end)
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.sort()
  end

  @doc """
  Returns all registered codec names (including unavailable ones).
  """
  @spec all_codecs() :: [atom()]
  def all_codecs do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.sort()
  end

  @doc """
  Checks if a codec is supported and available.
  """
  @spec supports?(atom()) :: boolean()
  def supports?(name) when is_atom(name) do
    case lookup(name) do
      {:ok, {module, _category, _info}} -> module != nil
      {:error, :unsupported_codec} -> false
    end
  end

  @doc """
  Returns detailed information about a codec.
  """
  @spec codec_info(atom()) :: {:ok, ExCodecs.Codec.t()} | {:error, :unsupported_codec}
  def codec_info(name) when is_atom(name) do
    case lookup(name) do
      {:ok, {_module, _category, info}} -> {:ok, info}
      {:error, :unsupported_codec} -> {:error, :unsupported_codec}
    end
  end

  @doc """
  Returns all codecs in a given category.
  """
  @spec codecs_by_category(atom()) :: [ExCodecs.Codec.t()]
  def codecs_by_category(category) when is_atom(category) do
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {_name, {_module, cat, _info}} -> cat == category end)
    |> Enum.map(fn {_name, {_module, _cat, info}} -> info end)
    |> Enum.sort_by(& &1.name)
  end

  defp build_codec_info(name, module, category) do
    info =
      if function_exported?(module, :__codec_info__, 0) do
        module.__codec_info__()
      else
        %ExCodecs.Codec{}
      end

    %ExCodecs.Codec{
      name: name,
      category: category,
      module: module,
      native?: info.native?,
      streaming?: info.streaming?,
      configurable?: info.configurable?,
      version: info.version
    }
  end
end
