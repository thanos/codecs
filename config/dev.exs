import Config

config :ex_codecs,
  log_level: :debug

config :ex_codecs, ExCodecs.CodecRegistry, registry_table: :ex_codecs_registry
