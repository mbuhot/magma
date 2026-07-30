defmodule Magma.Dsl.Await do
  @moduledoc """
  The `await` entity: a step that waits for a signal.

      await :confirmation do
        signal "confirm"
        timeout :timer.hours(48)
        argument :quote, result(:quote)
      end

  It is an ordinary node in the graph. It takes arguments, downstream steps read
  `result(:confirmation)`, and `wait_for` orders it against steps it reads nothing from.

  `timeout` may be resolved at run time, so a cooling-off period can come from an argument.

  It cannot sit inside `group`, `around`, `recurse` or `compose`. Mutually exclusive outcomes
  are one wait whose signal payload or timeout discriminates the result — see `usage-rules.md`.
  """

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            arguments: [],
            block_ms: nil,
            description: nil,
            guards: [],
            name: nil,
            on_timeout: :error,
            signal: nil,
            timeout: nil

  @type resolver(value) :: value | (map(), map() -> value) | mfa()

  @type t :: %__MODULE__{
          arguments: [Reactor.Dsl.Argument.t()],
          block_ms: nil | non_neg_integer(),
          description: nil | String.t(),
          guards: [Reactor.Guard.Build.t()],
          name: atom(),
          on_timeout: :error | :return,
          signal: String.t(),
          timeout: nil | resolver(pos_integer())
        }

  @doc false
  def __entity__ do
    %Spark.Dsl.Entity{
      name: :await,
      describe: "Waits for a signal delivered by `Magma.signal/3`.",
      examples: [
        """
        await :confirmation, signal: "confirm", timeout: :timer.hours(48) do
          argument :quote, result(:quote)
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
        signal: [
          type: :string,
          required: true,
          doc: "The name `Magma.signal/3` delivers under."
        ],
        timeout: [
          type: {:or, [:pos_integer, {:fun, 2}, :mfa]},
          doc:
            "How long the wait may last in milliseconds, or something that answers with one at run time."
        ],
        block_ms: [
          type: :non_neg_integer,
          doc:
            "How long to hold the process before releasing the job. " <>
              "Defaults to `config :magma, :block_ms`, itself 5000."
        ],
        on_timeout: [
          type: {:in, [:error, :return]},
          default: :error,
          doc: "`:error` fails the run at the deadline. `:return` yields `:timeout` to branch on."
        ],
        description: [type: :string, doc: "What this wait is for."]
      ]
    }
  end

  defimpl Reactor.Dsl.Build do
    def build(await, reactor) do
      options = [
        signal: await.signal,
        timeout: await.timeout,
        block_ms: await.block_ms,
        on_timeout: await.on_timeout
      ]

      Reactor.Builder.add_step(
        reactor,
        await.name,
        {Magma.Step.Await, options},
        await.arguments,
        async?: true,
        description: await.description,
        guards: await.guards,
        max_retries: 0,
        ref: :step_name
      )
    end

    def verify(_await, _dsl_state), do: :ok
  end
end
