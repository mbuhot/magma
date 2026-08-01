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
      source_url: @source_url,
      homepage_url: @source_url
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
      {:reactor, github: "ash-project/reactor", override: true},
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
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "docs/tutorial.md": [title: "Tutorial"],
        "DECISIONS.md": [title: "Design decisions"]
      ],
      groups_for_extras: [
        Guides: ["README.md", "docs/tutorial.md"],
        Reference: ["DECISIONS.md"]
      ],
      groups_for_modules: [
        "Writing workflows": [
          Magma,
          Magma.Dsl,
          Magma.Testing
        ],
        "DSL entities": [
          Magma.Dsl.Await,
          Magma.Dsl.Dispatch,
          Magma.Dsl.Poll
        ],
        Steps: [
          Magma.Step.Await,
          Magma.Step.Dispatch,
          Magma.Step.Poll
        ],
        "The store": [
          Magma.Resource.Workflow,
          Magma.Resource.Checkpoint,
          Magma.Resource.Signal,
          Magma.Resource.Waiter,
          Magma.Store
        ],
        "Types and errors": [
          Magma.Status,
          Magma.Waiting,
          Magma.Type.Term,
          Magma.TimeoutError
        ],
        Operating: [
          Magma.Worker,
          Magma.Middleware,
          Magma.Retention,
          Magma.Pruner
        ]
      ],
      nest_modules_by_prefix: [Magma.Dsl, Magma.Resource, Magma.Step],
      skip_undefined_reference_warnings_on: ["DECISIONS.md"]
    ]
  end
end
