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
  """

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            arguments: [],
            block_ms: 5_000,
            description: nil,
            guards: [],
            name: nil,
            on_timeout: :error,
            signal: nil,
            timeout: nil

  @type t :: %__MODULE__{
          arguments: [Reactor.Dsl.Argument.t()],
          block_ms: non_neg_integer(),
          description: nil | String.t(),
          guards: [Reactor.Guard.Build.t()],
          name: atom(),
          on_timeout: :error | :return,
          signal: String.t(),
          timeout: nil | pos_integer()
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
        timeout: [type: :pos_integer, doc: "How long the wait may last, in milliseconds."],
        block_ms: [
          type: :non_neg_integer,
          default: 5_000,
          doc: "How long to hold the process before releasing the job."
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
        async?: false,
        description: await.description,
        guards: await.guards,
        max_retries: 0,
        ref: :step_name
      )
    end

    def verify(_await, _dsl_state), do: :ok
  end
end
