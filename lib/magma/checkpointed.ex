defmodule Magma.Checkpointed do
  @moduledoc false

  # The step implementation magma wraps every step in.
  #
  # A recorded output comes back from here rather than from a guard, which matters: Reactor
  # keeps a guard-skipped step off its undo stack, so a replayed value returned that way could
  # never be taken back. Returning it through `run/3` makes the step an ordinary success — it
  # lands on the undo stack, stores an intermediate result, and unwinds with everything else.
  #
  # Every other callback delegates to the step this wraps.

  use Reactor.Step

  alias Magma.Run

  @impl true
  def run(arguments, context, options) do
    name = Keyword.fetch!(options, :magma_name)

    case Run.recorded(context, name) do
      {:ok, output} -> {:ok, output}
      :miss -> run_inner(arguments, context, options, name)
    end
  end

  defp run_inner(arguments, context, options, name) do
    inner = inner_step(context, options)

    inner
    |> Reactor.Step.run(arguments, %{context | current_step: inner})
    |> handle(context, name)
  end

  # A step that returns steps is planning, and holds no checkpoint of its own. Its children
  # join the outer plan, so they are decorated here and carry checkpoints instead.
  defp handle({:ok, value, steps}, context, _name) when is_list(steps) do
    {:ok, value, Enum.map(steps, &Run.decorate_step(&1, context))}
  end

  defp handle({:ok, value}, context, name) do
    case Run.record(context, name, value) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle(other, _context, _name), do: other

  @impl true
  def compensate(reason, arguments, context, options) do
    inner = inner_step(context, options)
    name = Keyword.fetch!(options, :magma_name)

    case Reactor.Step.compensate(inner, reason, arguments, %{context | current_step: inner}) do
      {:continue, value} ->
        case Run.record(context, name, value) do
          :ok -> {:continue, value}
          {:error, error} -> {:error, error}
        end

      other ->
        other
    end
  end

  @impl true
  def undo(value, arguments, context, options) do
    inner = inner_step(context, options)
    name = Keyword.fetch!(options, :magma_name)

    case Reactor.Step.undo(inner, value, arguments, %{context | current_step: inner}) do
      :ok -> Run.mark_undone(context, name)
      other -> other
    end
  end

  @impl true
  def can?(%{impl: {__MODULE__, options}} = step, capability) do
    Reactor.Step.can?(%{step | impl: Keyword.fetch!(options, :magma_inner)}, capability)
  end

  def can?(step, capability), do: super(step, capability)

  @impl true
  def async?(%{impl: {__MODULE__, options}} = step) do
    Reactor.Step.async?(%{step | impl: Keyword.fetch!(options, :magma_inner)})
  end

  def async?(step), do: super(step)

  @impl true
  def nested_steps(options) do
    case Keyword.fetch!(options, :magma_inner) do
      {module, inner_options} -> nested_steps(module, inner_options)
      module -> nested_steps(module, [])
    end
  end

  defp nested_steps(module, inner_options) do
    if function_exported?(module, :nested_steps, 1) do
      module.nested_steps(inner_options)
    else
      []
    end
  end

  defp inner_step(context, options) do
    %{context.current_step | impl: Keyword.fetch!(options, :magma_inner)}
  end
end
