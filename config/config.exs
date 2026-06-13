import Config

config :ex_codecs,
  codecs: [
    zstd: {ExCodecs.Compression.Zstd, :compression},
    lz4: {ExCodecs.Compression.Lz4, :compression},
    snappy: {ExCodecs.Compression.Snappy, :compression},
    bzip2: {ExCodecs.Compression.Bzip2, :compression},
    blosc2: {ExCodecs.Compression.Blosc2, :compression}
  ]

import_config "#{config_env()}.exs"
