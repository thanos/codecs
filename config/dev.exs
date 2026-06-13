import Config

config :ex_codecs,
  log_level: :debug

config :rustler_precompiled, :force_build, ex_codecs: true
