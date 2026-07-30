import Config

config :helpdesk, ecto_repos: [Helpdesk.Repo]
config :helpdesk, ash_domains: [Helpdesk.Accounts, Helpdesk.Support, Helpdesk.Magma]

config :magma, domain: Helpdesk.Magma, repo: Helpdesk.Repo

config :helpdesk, Helpdesk.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "helpdesk_#{config_env()}",
  pool_size: 10

config :helpdesk, Oban,
  repo: Helpdesk.Repo,
  queues: [escalations: 10]

config :helpdesk, HelpdeskWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: Helpdesk.PubSub,
  render_errors: [formats: [html: HelpdeskWeb.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("magma-helpdesk-secret", 4),
  live_view: [signing_salt: "hQ4mZ7dK"],
  server: true

config :phoenix, :json_library, Jason

config :logger, level: :info

if config_env() == :test do
  config :helpdesk, Helpdesk.Repo, pool: Ecto.Adapters.SQL.Sandbox
  config :helpdesk, Oban, repo: Helpdesk.Repo, testing: :manual, queues: false, plugins: false
  config :helpdesk, HelpdeskWeb.Endpoint, server: false, http: [port: 4002]
  config :magma, block_ms: 0
  config :ash, :missed_notifications, :ignore
  config :logger, level: :warning
end
