defmodule ExCodecs.Application do
  @moduledoc """
  OTP Application callback module for ExCodecs.

  Starts the `ExCodecs.CodecRegistry` and registers all built-in codecs
  during application startup.
  """

  use Application

  @impl true
  @doc """
  Starts the ExCodecs supervision tree.

  This callback starts `ExCodecs.CodecRegistry`, registers every built-in
  compression codec, and supervises the registry with a `:one_for_one`
  strategy. It is invoked by OTP when the `:ex_codecs` application starts;
  application code should normally use `Application.ensure_all_started/1`
  instead of calling this function directly.

  ## Arguments

    * `type` — `Application.start_type()`. OTP supplies `:normal`,
      `{:takeover, node}`, or `{:failover, node}`; ExCodecs does not vary its
      startup behavior by type.
    * `args` — startup term configured for the application. ExCodecs ignores
      this value.

  ## Returns

    * `{:ok, supervisor_pid}` when the supervisor and registry start.
    * `{:error, reason}` when `Supervisor.start_link/2` cannot start the
      supervision tree.
    * `{:ok, supervisor_pid, state}` is permitted by the
      `Application.start/2` callback contract, but ExCodecs does not currently
      return that form.

  ## Raises

  This callback does not deliberately raise. OTP or supervisor internals may
  exit the calling process for unrecoverable startup failures.

  ## Example

      iex> {:ok, _apps} = Application.ensure_all_started(:ex_codecs)
      iex> Process.whereis(ExCodecs.Supervisor) |> is_pid()
      true
      iex> ExCodecs.supports?(:zstd)
      true

  ## Callback implementation

  An OTP application that embeds a similar registry can use the same shape:

      defmodule MyApp.Application do
        use Application

        @impl Application
        def start(_type, _args) do
          children = [{ExCodecs.CodecRegistry, register: fn -> :ok end}]
          Supervisor.start_link(children,
            strategy: :one_for_one,
            name: MyApp.Supervisor
          )
        end
      end
  """
  @spec start(Application.start_type(), term()) ::
          {:ok, pid()} | {:error, term()} | {:ok, pid(), term()}
  def start(_type, _args) do
    children = [
      {ExCodecs.CodecRegistry, register: &register_all_codecs/0}
    ]

    opts = [strategy: :one_for_one, name: ExCodecs.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        {:ok, pid}

      error ->
        error
    end
  end

  @doc false
  def register_all_codecs do
    codecs = [
      {:zstd, ExCodecs.Compression.Zstd, :compression},
      {:lz4, ExCodecs.Compression.Lz4, :compression},
      {:snappy, ExCodecs.Compression.Snappy, :compression},
      {:bzip2, ExCodecs.Compression.Bzip2, :compression},
      {:blosc2, ExCodecs.Compression.Blosc2, :compression}
    ]

    nif_ok? = ExCodecs.Native.nif_loaded?()

    for {name, module, category} <- codecs do
      native? =
        function_exported?(module, :__codec_info__, 0) and
          match?(%{native?: true}, module.__codec_info__())

      loadable? =
        Code.ensure_loaded?(module) and function_exported?(module, :encode, 2) and
          function_exported?(module, :decode, 2)

      if loadable? and (not native? or nif_ok?) do
        ExCodecs.CodecRegistry.register(name, module, category)
      else
        ExCodecs.CodecRegistry.register_unavailable(name, category)
      end
    end

    :ok
  end
end
