defmodule Magma.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mbuhot/magma"

  def project do
    [
      app: :magma,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: "Durable workflows for Ash: a Reactor checkpointed inside an Oban job.",
      package: package(),
      docs: docs(),
      name: "Magma",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.30"},
      {:ash_postgres, "~> 2.11"},
      {:reactor, "~> 1.0"},
      {:oban, "~> 2.19"},
      {:igniter, "~> 0.6", optional: true},
      {:usage_rules, "~> 0.1", only: [:dev]},
      {:ex_doc, "~> 0.34", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.create --quiet", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "DECISIONS.md"]
    ]
  end
end
