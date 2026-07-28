defmodule Magma.Run do
  @moduledoc """
  Turns a reactor into a durable one and runs it.

  Decoration happens before `Reactor.run/4` and touches nothing but the built `%Reactor{}`.
  Reactor's planner, executor loop and concurrency are left exactly as they are, so the graph
  that runs is the one the DSL describes.
  """

  alias Magma.Key
  alias Magma.Store

  defstruct [:workflow_id, :checkpoints]

  @type t :: %__MODULE__{workflow_id: String.t(), checkpoints: %{binary() => term()}}

  @doc """
  Runs a workflow's reactor, replaying whatever it has already recorded.

  Checkpoints load once, here, so a step's lookup during the run costs a map read.
  """
  @spec run(Ash.Resource.record(), keyword()) ::
          {:ok, term()} | {:halted, Reactor.t()} | {:error, term()}
  def run(workflow, options \\ []) do
    state = %__MODULE__{
      workflow_id: workflow.id,
      checkpoints: Map.new(Store.checkpoints(workflow.id), fn {key, row} -> {key, row.output} end)
    }

    context = %{
      magma: state,
      actor: workflow.actor,
      tenant: workflow.tenant
    }

    workflow.module
    |> Reactor.Info.to_struct!()
    |> decorate(context)
    |> Reactor.run(workflow.inputs || %{}, context, options)
  end

  @doc "Wraps every step, rewrites its guards, and seeds the context."
  @spec decorate(Reactor.t(), map()) :: Reactor.t()
  def decorate(reactor, context) do
    %{
      reactor
      | middleware: [Magma.Middleware | reactor.middleware],
        context: Map.merge(reactor.context, context),
        steps: Enum.map(reactor.steps, &decorate_step(&1, context))
    }
  end

  @doc """
  Wraps one step.

  Also used for steps a composite returns at run time, so a `map` element or a `switch`
  branch carries a checkpoint of its own.
  """
  @spec decorate_step(Reactor.Step.t(), map()) :: Reactor.Step.t()
  def decorate_step(%Reactor.Step{impl: {Magma.Checkpointed, _options}} = step, _context),
    do: step

  def decorate_step(%Reactor.Step{} = step, context) do
    reject_unsupported!(step)

    %{
      step
      | impl: {Magma.Checkpointed, magma_inner: step.impl, magma_name: step.name},
        guards: Enum.map(step.guards, &neutralise(&1, step.name, context))
    }
  end

  # A recorded step keeps the answer its guards gave the first time, so a `where` reading the
  # clock or the database cannot contradict a decision already acted on.
  defp neutralise(%Reactor.Guard{} = guard, name, _context) do
    original = guard.fun

    %{
      guard
      | fun: fn arguments, context ->
          case recorded(context, name) do
            {:ok, _output} -> :cont
            :miss -> apply_guard(original, arguments, context)
          end
        end
    }
  end

  defp apply_guard({m, f, a}, arguments, context), do: apply(m, f, [arguments, context | a])
  defp apply_guard(fun, arguments, context) when is_function(fun, 2), do: fun.(arguments, context)

  defp reject_unsupported!(%Reactor.Step{impl: {Reactor.Step.Compose, options}} = step) do
    if options[:support_undo?] do
      raise """
      #{inspect(step.name)} composes a reactor with `support_undo?: true`, which magma cannot \
      checkpoint.

      Asked to support undo, `compose` records `%{reactor: reactor}` — a live `%Reactor{}` \
      carrying references, closures and a plan. Nothing magma stored of it could be replayed \
      into an undo that works.

      Compose without undo support, or lift the steps into this reactor so each one \
      checkpoints on its own.
      """
    end
  end

  defp reject_unsupported!(_step), do: :ok

  @doc "What a step recorded on an earlier attempt, if anything."
  @spec recorded(map(), term()) :: {:ok, term()} | :miss
  def recorded(%{magma: %__MODULE__{checkpoints: checkpoints}}, name) do
    case Map.fetch(checkpoints, Key.for(name)) do
      {:ok, output} -> {:ok, output}
      :error -> :miss
    end
  end

  def recorded(_context, _name), do: :miss

  @doc "Writes what a step produced."
  @spec record(map(), term(), term()) :: :ok | {:error, term()}
  def record(%{magma: %__MODULE__{workflow_id: workflow_id}}, name, output) do
    case Store.record(workflow_id, name, output) do
      {:ok, _checkpoint} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Marks a step's checkpoint as taken back."
  @spec mark_undone(map(), term()) :: :ok | {:error, term()}
  def mark_undone(%{magma: %__MODULE__{workflow_id: workflow_id}}, name) do
    key = Key.for(name)

    case Enum.find(Store.standing(workflow_id), &(&1.step_key == key)) do
      nil ->
        :ok

      checkpoint ->
        case Store.mark_undone(checkpoint) do
          {:ok, _marked} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
