defmodule ExCodecs.Spatial.Codec.StreamSource do
  @moduledoc false

  # Shared `:source` resolution for spatial stream_decode paths.
  # Default is `:binary`; `:file` and `:auto` are explicit opt-ins.

  alias ExCodecs.Spatial.Accel

  @type codec :: :spatial_binary | :gsplat | :ply
  @type resolved :: {:ok, :binary | :file, binary()} | {:error, ExCodecs.Error.t()}

  @spec resolve(binary(), keyword(), codec(), (binary() -> boolean())) :: resolved()
  def resolve(bin, opts, codec, path_like?)
      when is_binary(bin) and is_function(path_like?, 1) and
             codec in [:spatial_binary, :gsplat, :ply] do
    case Keyword.get(opts, :source, :binary) do
      :binary ->
        {:ok, :binary, bin}

      :file ->
        {:ok, :file, bin}

      :auto ->
        if path_like?.(bin) and File.regular?(bin) do
          {:ok, :file, bin}
        else
          {:ok, :binary, bin}
        end

      other ->
        {:error,
         ExCodecs.Error.new(:invalid_options,
           codec: codec,
           message: "Unsupported :source #{inspect(other)}; use :binary, :file, or :auto"
         )}
    end
  end

  @spec path_like?(binary(), (binary() -> boolean()), [String.t()]) :: boolean()
  def path_like?(bin, magic?, extensions)
      when is_binary(bin) and is_function(magic?, 1) and is_list(extensions) do
    byte_size(bin) < 4096 and not magic?.(bin) and
      (String.contains?(bin, "/") or String.contains?(bin, "\\") or
         String.ends_with?(bin, extensions))
  end

  @spec accel?(keyword()) :: boolean()
  def accel?(opts) when is_list(opts) do
    Keyword.get(opts, :accel, true) != false and Accel.available?()
  end
end
