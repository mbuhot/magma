import Config

config :agency, ecto_repos: [Agency.Repo]
config :agency, ash_domains: [Agency.Sale, Agency.Magma]

config :magma, domain: Agency.Magma, repo: Agency.Repo

config :agency, Agency.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "agency_#{config_env()}",
  pool_size: 10

config :agency, Oban,
  repo: Agency.Repo,
  queues: []

config :agency, AgencyWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: Agency.PubSub,
  render_errors: [formats: [html: AgencyWeb.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("magma-agency-secret", 4),
  live_view: [signing_salt: "hQ4mZ7dK"],
  server: true

config :phoenix, :json_library, Jason

config :logger, level: :info

if config_env() == :test do
  config :agency, Agency.Repo, pool: Ecto.Adapters.SQL.Sandbox
  config :agency, Oban, repo: Agency.Repo, testing: :manual, queues: false, plugins: false
  config :agency, AgencyWeb.Endpoint, server: false, http: [port: 4002]
  config :magma, block_ms: 0
  config :ash, :missed_notifications, :ignore
  config :logger, level: :warning
end
