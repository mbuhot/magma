import Config

config :payouts, ecto_repos: [Payouts.Repo]
config :payouts, ash_domains: [Payouts.Offramp, Payouts.Magma]

config :magma, domain: Payouts.Magma, repo: Payouts.Repo

config :payouts, Payouts.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "payouts_#{config_env()}",
  pool_size: 10

config :payouts, Oban,
  repo: Payouts.Repo,
  queues: [payouts: 10, rails: 5, onboarding: 5]

config :payouts, :rails, %{"EUR" => Payouts.Rails.Bridge, "USD" => Payouts.Rails.Meridian}

config :payouts, :onboarding, %{
  "EUR" => Payouts.Onboarding.Bridge,
  "USD" => Payouts.Onboarding.Meridian
}

config :payouts, :beneficiaries, %{"EUR" => Payouts.Beneficiaries.Bridge}

config :payouts, PayoutsWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: Payouts.PubSub,
  render_errors: [formats: [html: PayoutsWeb.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("magma-console-secret", 4),
  live_view: [signing_salt: "vN8pQ2rT"],
  server: true

config :phoenix, :json_library, Jason

config :logger, level: :info

if config_env() == :test do
  config :payouts, Payouts.Repo, pool: Ecto.Adapters.SQL.Sandbox
  config :payouts, Oban, repo: Payouts.Repo, testing: :manual, queues: false, plugins: false
  config :payouts, PayoutsWeb.Endpoint, server: false, http: [port: 4002]
  config :magma, block_ms: 0
  config :ash, :missed_notifications, :raise
  config :logger, level: :warning
end
