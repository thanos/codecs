import Config

# Force local NIF compilation in all environments. This ensures CI and local
# dev always build from source. It does NOT affect downstream users — their own
# config takes precedence. Once precompiled artifacts are published to GitHub
# Releases, end users will download them automatically via RustlerPrecompiled.
config :rustler_precompiled, :force_build, ex_codecs: true

import_config "#{config_env()}.exs"
