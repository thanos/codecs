import Config

config :livebook, LivebookWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost", path: "/"],
  pubsub_server: Livebook.PubSub,
  live_view: [signing_salt: "livebook"],
  drainer: [shutdown: 1000],
  render_errors: [formats: [html: LivebookWeb.ErrorHTML], layout: false]

config :logger, :default_formatter,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, JSON

config :mime, :types, %{
  "audio/m4a" => ["m4a"],
  "text/plain" => ["livemd"]
}

config :livebook,
  agent_name: "default",
  allowed_uri_schemes: [],
  app_service_name: nil,
  app_service_url: nil,
  apps_banner: nil,
  authentication: :token,
  aws_credentials: false,
  feature_flags: [],
  force_ssl_host: nil,
  learn_notebooks: [],
  plugs: [],
  rewrite_on: [],
  shutdown_callback: nil,
  teams_auth: nil,
  teams_url: "https://teams.livebook.dev",
  within_iframe: false

config :livebook, Livebook.Apps.Manager, retry_backoff_base_ms: 5_000

config :livebook_test,
  paths: ["livebooks/**/*.livemd"],
  dependency_mode: :local,
  local_deps: [ex_codecs: "."],
  timeout: 120_000
