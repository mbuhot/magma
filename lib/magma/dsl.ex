defmodule Magma.Dsl do
  @moduledoc """
  The entities magma adds to a Reactor.

      use Reactor, extensions: [Magma.Dsl]

      magma do
        queue :payments
        max_attempts 20
      end

      step :confirmation, {Magma.Step.Await, signal: "confirm", timeout: :timer.hours(48)}

  Every existing Reactor entity keeps its meaning. A reactor written without any of this still
  runs durably, since the decoration happens at run time on the built `%Reactor{}`.
  """

  @magma %Spark.Dsl.Section{
    name: :magma,
    describe: "How this workflow's job is enqueued.",
    schema: [
      queue: [type: :atom, default: :default, doc: "The Oban queue the job runs on."],
      max_attempts: [
        type: :pos_integer,
        default: 20,
        doc: "How many times a crashed run is brought back before Oban gives up."
      ],
      retention: [
        type: {:or, [:pos_integer, {:in, [:infinity]}]},
        doc: """
        How long a finished workflow's rows are kept, in milliseconds. Falls back to
        `config :magma, retention: ...`, and to `:infinity` if neither is set.
        """
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@magma]
end
