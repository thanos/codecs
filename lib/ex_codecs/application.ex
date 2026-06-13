defmodule ExCodecs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExCodecs.CodecRegistry
    ]

    opts = [strategy: :one_for_one, name: ExCodecs.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        register_all_codecs()
        {:ok, pid}

      error ->
        error
    end
  end

  defp register_all_codecs do
    codecs = [
      {:zstd, ExCodecs.Compression.Zstd, :compression},
      {:lz4, ExCodecs.Compression.Lz4, :compression},
      {:snappy, ExCodecs.Compression.Snappy, :compression},
      {:bzip2, ExCodecs.Compression.Bzip2, :compression},
      {:blosc2, ExCodecs.Compression.Blosc2, :compression}
    ]

    for {name, module, category} <- codecs do
      if Code.ensure_loaded?(module) and function_exported?(module, :encode, 2) do
        ExCodecs.CodecRegistry.register(name, module, category)
      else
        ExCodecs.CodecRegistry.register_unavailable(name, category)
      end
    end
  end
end
