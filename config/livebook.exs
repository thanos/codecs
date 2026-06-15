import Config

config :livebook_test,
  paths: ["livebooks/**/*.livemd"],
  dependency_mode: :local,
  local_deps: [ex_codecs: "."],
  timeout: 120_000
