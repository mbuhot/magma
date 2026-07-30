defmodule Magma.Dsl.Poll do
  @moduledoc """
  The `poll` entity: a step that checks a condition on an interval until it holds.

      poll :settlement do
        every :timer.seconds(30)
        until &Provider.settled?/2
        argument :transfer, result(:transfer)
      end

  `until` receives the step's arguments and the reactor context, and answers `{:ok, value}` or
  `:not_yet`.

  It cannot sit inside `group`, `around`, `recurse` or `compose`. A status that discriminates
  several outcomes is the natural shape for the value it returns — see `usage-rules.md`.
  """

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            arguments: [],
            description: nil,
            every: 30_000,
            guards: [],
            name: nil,
            until: nil

  @type t :: %__MODULE__{
          arguments: [Reactor.Dsl.Argument.t()],
          description: nil | String.t(),
          every: pos_integer(),
          guards: [Reactor.Guard.Build.t()],
          name: atom(),
          until: (map(), map() -> {:ok, any()} | :not_yet) | mfa()
        }

  @doc false
  def __entity__ do
    %Spark.Dsl.Entity{
      name: :poll,
      describe: "Checks a condition on an interval until it holds.",
      examples: [
        """
        poll :settlement, every: :timer.seconds(30), until: &Provider.settled?/2 do
          argument :transfer, result(:transfer)
        end
        """
      ],
      target: __MODULE__,
      args: [:name],
      identifier: :name,
      imports: [Reactor.Dsl.Argument],
      recursive_as: :steps,
      entities: [
        arguments: [Reactor.Dsl.Argument.__entity__(), Reactor.Dsl.WaitFor.__entity__()],
        guards: [Reactor.Dsl.Where.__entity__(), Reactor.Dsl.Guard.__entity__()]
      ],
      schema: [
        name: [type: :atom, required: true, doc: "A name unique within this reactor."],
        until: [
          type: {:or, [{:fun, 2}, :mfa]},
          required: true,
          doc: "Answers `{:ok, value}` when the condition holds, and `:not_yet` otherwise."
        ],
        every: [
          type: :pos_integer,
          default: 30_000,
          doc: "How long to wait between checks, in milliseconds."
        ],
        description: [type: :string, doc: "What this poll is waiting on."]
      ]
    }
  end

  defimpl Reactor.Dsl.Build do
    def build(poll, reactor) do
      Reactor.Builder.add_step(
        reactor,
        poll.name,
        {Magma.Step.Poll, until: poll.until, every: poll.every},
        poll.arguments,
        async?: false,
        description: poll.description,
        guards: poll.guards,
        max_retries: 0,
        ref: :step_name
      )
    end

    def verify(_poll, _dsl_state), do: :ok
  end
end
