defmodule Magma.Dsl.Dispatch do
  @moduledoc """
  The `dispatch` entity: a step that runs another workflow as a durable child.

      dispatch :rail do
        workflow &MyApp.Routing.rail_for/2
        queue :rails
        argument :transfer, result(:transfer)
      end

  The child gets its own row, its own job and its own queue, and this step holds the result it
  returned. `workflow`, `inputs` and `timeout` may each be resolved at run time, so the module a
  payout reaches for can come from config or from an argument.

  It cannot sit inside `group`, `around`, `recurse` or `compose`. A child's failure reaches the
  caller as a `Magma.ChildError` and unwinds it, so an expected failure is a return value the
  child completes with — see `usage-rules.md`.
  """

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            arguments: [],
            block_ms: nil,
            description: nil,
            guards: [],
            inputs: nil,
            name: nil,
            queue: :default,
            timeout: nil,
            workflow: nil

  @type resolver(value) :: value | (map(), map() -> value) | mfa()

  @type t :: %__MODULE__{
          arguments: [Reactor.Dsl.Argument.t()],
          block_ms: nil | non_neg_integer(),
          description: nil | String.t(),
          guards: [Reactor.Guard.Build.t()],
          inputs: nil | resolver(map()),
          name: atom(),
          queue: atom(),
          timeout: nil | resolver(pos_integer()),
          workflow: resolver(module())
        }

  @doc false
  def __entity__ do
    %Spark.Dsl.Entity{
      name: :dispatch,
      describe: "Runs another workflow as a durable child and waits for its result.",
      examples: [
        """
        dispatch :rail do
          workflow &MyApp.Routing.rail_for/2
          queue :rails
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
        workflow: [
          type: {:or, [:module, {:fun, 2}, :mfa]},
          required: true,
          doc: "The child's module, or something that answers with one at run time."
        ],
        inputs: [
          type: {:or, [:map, {:fun, 2}, :mfa]},
          doc: "What the child is started with. Defaults to this step's arguments."
        ],
        queue: [type: :atom, default: :default, doc: "The Oban queue the child runs on."],
        timeout: [
          type: {:or, [:pos_integer, {:fun, 2}, :mfa]},
          doc:
            "How long to wait for the child in milliseconds, or something that answers with one at run time."
        ],
        block_ms: [
          type: :non_neg_integer,
          doc:
            "How long to hold the process before releasing the job. " <>
              "Defaults to `config :magma, :block_ms`, itself 5000."
        ],
        description: [type: :string, doc: "What this child is for."]
      ]
    }
  end

  defimpl Reactor.Dsl.Build do
    def build(dispatch, reactor) do
      options = [
        workflow: dispatch.workflow,
        inputs: dispatch.inputs,
        queue: dispatch.queue,
        timeout: dispatch.timeout,
        block_ms: dispatch.block_ms
      ]

      Reactor.Builder.add_step(
        reactor,
        dispatch.name,
        {Magma.Step.Dispatch, options},
        dispatch.arguments,
        async?: false,
        description: dispatch.description,
        guards: dispatch.guards,
        max_retries: 0,
        ref: :step_name
      )
    end

    def verify(_dispatch, _dsl_state), do: :ok
  end
end
