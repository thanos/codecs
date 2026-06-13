# coveralls-ignore-start
defmodule ExCodecs.Native do
  @moduledoc """
  Native NIF module providing Rust-based compression implementations.

  This module loads precompiled NIF binaries for Zstd, LZ4, Snappy, Bzip2,
  and Blosc2 compression/decompression via `RustlerPrecompiled`. If a precompiled
  artifact is not available for the current platform, it falls back to compiling
  the Rust NIF from source (requires the Rust toolchain).

  If the NIF fails to load entirely, all functions fall back to
  `:erlang.nif_error(:nif_not_loaded)`, and codecs are registered as unavailable
  at startup.

  > **Note**: This module is excluded from coverage because all functions are
  > Rustler NIF stubs that are replaced at load time by the native implementation.
  """

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :ex_codecs,
    crate: :ex_codecs_native,
    version: version,
    base_url: "https://github.com/thanos/codecs/releases/download/v#{version}",
    mode: :release,
    nif_versions: ["2.17"],
    targets: [
      "aarch64-apple-darwin",
      "x86_64-apple-darwin",
      "x86_64-unknown-linux-gnu",
      "x86_64-unknown-linux-musl",
      "aarch64-unknown-linux-gnu",
      "aarch64-unknown-linux-musl",
      "x86_64-pc-windows-msvc"
    ]

  @doc false
  def zstd_compress(_data, _level), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def zstd_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def lz4_compress(_data), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def lz4_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def snappy_compress(_data), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def snappy_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def bzip2_compress(_data, _block_size), do: :erlang.nif_error(:nif_not_loaded)
  @doc false
  def bzip2_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def blosc2_compress(_data, _cname, _clevel, _shuffle, _typesize),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def blosc2_decompress(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def codec_versions, do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def nif_loaded?, do: not function_exported?(__MODULE__, :zstd_compress, 2)
end

# coveralls-ignore-stop
