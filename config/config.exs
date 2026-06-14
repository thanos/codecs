import Config

# In dev/test, build the NIF from source so `mix compile` and `mix test`
# work without precompiled artifacts. Release consumers use precompiled NIFs.
#
# CI and release workflows can also set EX_CODECS_BUILD=1 or
# RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=1 to force source compilation
# (e.g. the publish_hex job in .github/workflows/release.yml).
if config_env() in [:dev, :test] do
  config :rustler_precompiled, :force_build, ex_codecs: true
  import_config "#{config_env()}.exs"
end
