# coveralls-ignore-start
defmodule ExCodecs.Native do
  @moduledoc """
  Native NIF module providing Rust-based compression implementations via Rustler.

  This module loads precompiled NIF binaries for Zstd, LZ4, Snappy, Bzip2,
  and Blosc2 compression/decompression. If the NIF fails to load, all
  functions fall back to `:erlang.nif_error(:nif_not_loaded)`, and codecs
  are registered as unavailable at startup.

  > **Note**: This module is excluded from coverage because all functions are
  > Rustler NIF stubs that are replaced at load time by the native implementation.
  """

  use Rustler,
    otp_app: :ex_codecs,
    crate: :ex_codecs_native,
    mode: :release

  @doc false
  def zstd_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def zstd_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def lz4_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def lz4_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def snappy_compress(_data), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def snappy_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def bzip2_compress(_data, _block_size, _work_factor), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def bzip2_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def blosc2_compress(_data, _cname, _clevel, _shuffle, _typesize, _blocksize, _numthreads),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def blosc2_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def codec_versions, do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def nif_loaded?, do: not function_exported?(__MODULE__, :zstd_compress, 2)
end
# coveralls-ignore-stop
