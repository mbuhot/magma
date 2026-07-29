defmodule Magma.Step.Dispatch do
  @moduledoc """
  Runs another workflow as a durable child and waits for it.

  The child gets its own row, its own Oban job and its own queue, so a long rail runs on
  hardware sized for rails while the spine that dispatched it holds nothing.

  Its id is derived from this workflow and this step, so a replay adopts the child already
  running rather than starting a second one. That is what lets the *module* be decided at run
  time — from config, or from an argument — while the child's identity stays stable.

      dispatch :rail do
        workflow &MyApp.Routing.rail_for/2
        queue :rails
        argument :transfer, result(:transfer)
      end

  `workflow` is a module, or a two-arity function over the step's arguments and context that
  returns one. `inputs` is the same, defaulting to the step's arguments.
  """

  use Reactor.Step

  alias Magma.Run
  alias Magma.Store

  @impl true
  def run(arguments, context, options) do
    parent_id = workflow_id(context)
    name = context.current_step.name
    child_id = Magma.Key.child_id(parent_id, name)
    signal = signal_name(name)

    :ok = ensure_started(child_id, parent_id, signal, arguments, context, options)

    await(parent_id, signal, options)
  end

  # Starting is idempotent on the derived id, so a replay that gets this far finds the child
  # already there and falls through to waiting on it.
  defp ensure_started(child_id, parent_id, signal, arguments, context, options) do
    case Store.get_workflow(child_id) do
      {:ok, nil} -> start(child_id, parent_id, signal, arguments, context, options)
      {:ok, _running} -> :ok
    end
  end

  defp start(child_id, parent_id, signal, arguments, context, options) do
    module = resolve(Keyword.fetch!(options, :workflow), arguments, context)
    inputs = resolve_inputs(Keyword.get(options, :inputs), arguments, context)

    {:ok, _child} =
      Magma.start(module, inputs,
        workflow_id: child_id,
        parent: {parent_id, signal},
        queue: Keyword.get(options, :queue, :default),
        actor: context[:actor],
        tenant: context[:tenant]
      )

    :ok
  end

  defp await(parent_id, signal, options) do
    case Magma.Step.Await.run(
           %{},
           %{magma: %Run{workflow_id: parent_id, checkpoints: %{}}, current_step: nil},
           signal: signal,
           block_ms: Keyword.get(options, :block_ms),
           timeout: Keyword.get(options, :timeout),
           on_timeout: :error
         ) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, error}} -> {:error, error}
      other -> other
    end
  end

  defp signal_name(step_name), do: "magma.child." <> Magma.Key.label(step_name)

  defp resolve(fun, arguments, context) when is_function(fun, 2), do: fun.(arguments, context)
  defp resolve({m, f, a}, arguments, context), do: apply(m, f, [arguments, context | a])
  defp resolve(module, _arguments, _context) when is_atom(module), do: module

  defp resolve_inputs(nil, arguments, _context), do: arguments

  defp resolve_inputs(fun, arguments, context) when is_function(fun, 2),
    do: fun.(arguments, context)

  defp resolve_inputs(inputs, _arguments, _context) when is_map(inputs), do: inputs

  defp workflow_id(%{magma: %Run{workflow_id: id}}), do: id
end
