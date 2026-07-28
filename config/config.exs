import Config

if config_env() == :test do
  config :magma, ecto_repos: [Magma.TestRepo]

  config :magma, Magma.TestRepo,
    username: System.get_env("POSTGRES_USER", "postgres"),
    password: System.get_env("POSTGRES_PASSWORD", "postgres"),
    hostname: System.get_env("POSTGRES_HOST", "localhost"),
    database: "magma_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10

  config :magma, Oban,
    repo: Magma.TestRepo,
    testing: :manual,
    queues: false,
    plugins: false

  config :magma, domain: Magma.Test.Store, repo: Magma.TestRepo

  config :ash, :missed_notifications, :ignore

  config :logger, level: :warning
end
