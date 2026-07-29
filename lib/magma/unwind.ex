defmodule Magma.Unwind do
  @moduledoc false

  # Takes back the work a run left standing.
  #
  # Reactor owns unwinding inside a live run: it built the undo stack as steps completed and it
  # pops it when one fails. This drives the other case — a rollback that has to survive the
  # process it started in.
  #
  # `Reactor.run/4` accepts `:pending` and `:halted`, so a half-finished rollback has no entry
  # point in the executor. Rather than replay and poison, which cannot promise a parallel branch
  # gets reached before the error propagates, this walks the checkpoints directly.
  #
  # The `undone_at` marks are the progress log. A crash part way through leaves the remaining
  # standing checkpoints as they were, and the next attempt carries on from exactly there.

  require Logger

  alias Magma.Key
  alias Magma.Store

  @max_undo_count 5

  @doc """
  Takes back every checkpoint a workflow still has, newest first.

  A failed undo is an error and leaves its checkpoint standing, so what is still out there
  stays on the record. A checkpoint whose step cannot be resolved — a child an inlining
  composite generated at run time — is reported rather than raised, and also left standing: it
  should not hold a rollback open that has otherwise finished.
  """
  @spec run(Ash.Resource.record()) :: {:ok, [term()]} | {:error, [term()]}
  def run(workflow) do
    steps = resolvable_steps(workflow)
    standing = Store.standing(workflow.id)
    results = results_by_name(standing, steps)

    context = %{
      actor: workflow.actor,
      tenant: workflow.tenant,
      magma: %Magma.Run{workflow_id: workflow.id, checkpoints: %{}}
    }

    {unresolved, errors} =
      standing
      |> Enum.flat_map(&undo_checkpoint(&1, steps, results, workflow.inputs || %{}, context))
      |> Enum.split_with(&match?({:unresolved, _label}, &1))

    report(workflow, unresolved)

    case errors do
      [] -> {:ok, unresolved}
      errors -> {:error, errors}
    end
  end

  defp report(_workflow, []), do: :ok

  defp report(workflow, unresolved) do
    labels = Enum.map_join(unresolved, ", ", fn {:unresolved, label} -> label end)

    Logger.warning("""
    magma could not resolve #{length(unresolved)} checkpoint(s) while unwinding     #{workflow.id}, and has left them standing: #{labels}

    These belong to steps an inlining composite generated at run time. Their work has not been     taken back.
    """)
  end

  defp undo_checkpoint(checkpoint, steps, results, inputs, context) do
    case Map.fetch(steps, checkpoint.step_key) do
      :error ->
        [{:unresolved, checkpoint.step_label}]

      {:ok, step} ->
        undo(step, checkpoint, results, inputs, context)
    end
  end

  # A step with no undo was never on Reactor's stack either. Its effect stands, and its
  # checkpoint stands with it, so what is still out there stays on the record. This is what a
  # workflow carried forward rather than reversed relies on — an onboarding part-decided by a
  # provider is the thing a resumed run needs, and tearing it down would cost the customer
  # everything already sent.
  defp undo(step, checkpoint, results, inputs, context) do
    if Reactor.Step.can?(step, :undo) do
      drive(step, checkpoint, arguments(step, results, inputs), context)
    else
      []
    end
  end

  defp drive(step, checkpoint, arguments, context) do
    # Claim before undoing. Two rollbacks racing over one workflow would otherwise both read
    # the same standing row and both call undo/4, taking the work back twice.
    case Store.claim_undo(checkpoint) do
      {:ok, claimed} -> run_undo(step, claimed, arguments, context, 0)
      :taken -> []
    end
  end

  defp run_undo(step, checkpoint, _arguments, _context, @max_undo_count) do
    :ok = Store.release_undo(checkpoint)
    [{:undo_retries_exceeded, step.name}]
  end

  defp run_undo(step, checkpoint, arguments, context, attempt) do
    case Reactor.Step.undo(step, checkpoint.output, arguments, put_step(context, step)) do
      :ok ->
        []

      :retry ->
        run_undo(step, checkpoint, arguments, context, attempt + 1)

      {:retry, _reason} ->
        run_undo(step, checkpoint, arguments, context, attempt + 1)

      {:error, reason} ->
        :ok = Store.release_undo(checkpoint)
        [{:undo_failed, step.name, reason}]
    end
  end

  defp put_step(context, step), do: Map.put(context, :current_step, step)

  # Declared steps, whatever they nest, and the children an inlining composite generates. A
  # `map` element or a `switch` branch is materialised by driving its parent, which reads its
  # source and returns steps without doing anything of its own.
  defp resolvable_steps(workflow) do
    reactor = Reactor.Info.to_struct!(workflow.module)

    reactor.steps
    |> Enum.flat_map(&expand/1)
    |> Map.new(&{Key.for(&1.name), &1})
  end

  defp expand(%Reactor.Step{} = step) do
    [step | nested(step)]
  end

  defp nested(%Reactor.Step{impl: {module, options}}) do
    if function_exported?(module, :nested_steps, 1) do
      module.nested_steps(options) |> Enum.flat_map(&expand/1)
    else
      []
    end
  end

  defp nested(_step), do: []

  defp results_by_name(standing, steps) do
    Map.new(standing, fn checkpoint ->
      name =
        case Map.fetch(steps, checkpoint.step_key) do
          {:ok, step} -> step.name
          :error -> checkpoint.step_label
        end

      {name, checkpoint.output}
    end)
  end

  defp arguments(step, results, inputs) do
    step.arguments
    |> Enum.reject(&(&1.name == :_))
    |> Map.new(fn argument -> {argument.name, resolve(argument.source, results, inputs)} end)
  end

  defp resolve(%Reactor.Template.Result{name: name, sub_path: path}, results, _inputs) do
    results |> Map.get(name) |> dig(path)
  end

  defp resolve(%Reactor.Template.Input{name: name, sub_path: path}, _results, inputs) do
    inputs |> Map.get(name) |> dig(path)
  end

  defp resolve(%Reactor.Template.Value{value: value, sub_path: path}, _results, _inputs) do
    dig(value, path)
  end

  defp resolve(_template, _results, _inputs), do: nil

  defp dig(value, []), do: value
  defp dig(value, path), do: get_in(value, path)
end
