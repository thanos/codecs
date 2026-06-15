import Config

if config_env() in [:dev, :test] do
  config :rustler_precompiled, :force_build, ex_codecs: true
  import_config "#{config_env()}.exs"
end

if config_env() == :livebook do
  config :rustler_precompiled, :force_build, ex_codecs: true
  import_config "livebook.exs"
end
