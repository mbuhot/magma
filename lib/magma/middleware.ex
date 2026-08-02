defmodule Magma.Middleware do
  @moduledoc """
  The telemetry a durable run emits.

  | Event | Emitted when |
  |---|---|
  | `[:magma, :step, :step_complete]` | a step returns successfully |
  | `[:magma, :step, :step_error]` | a step returns an error |

  Measurements are `%{system_time: System.system_time()}`. Metadata is `%{step: name,
  workflow_id: id}`, where `step` is the step's declared name and `workflow_id` is `nil` for a
  reactor run outside magma.

  Attach to them as you would any telemetry event:

      :telemetry.attach("magma-steps", [:magma, :step, :step_complete], &handler/4, nil)

  A step failure that nothing can compensate is also written to the workflow's row from here,
  before the rollback it triggers takes anything back. That is what leaves the cause on the
  record for an attempt that finds a rollback already under way.
  """

  use Reactor.Middleware

  @impl true
  def event({:run_complete, _result}, step, context) do
    telemetry(:step_complete, step, context)
  end

  def event({:run_error, error}, step, context) do
    unless Reactor.Step.can?(step, :compensate), do: record_error(context, error)

    telemetry(:step_error, step, context)
  end

  def event({:run_halt, _value}, _step, context) do
    case workflow_id(context) do
      nil -> :ok
      workflow_id -> Magma.Notifier.halting(workflow_id)
    end
  end

  def event({:compensate_error, error}, _step, context) do
    record_error(context, error)
  end

  def event(_event, _step, _context), do: :ok

  @impl true
  def get_process_context, do: Process.get(:magma_context)

  @impl true
  def set_process_context(value) do
    Process.put(:magma_context, value)
    :ok
  end

  defp telemetry(event, step, context) do
    :telemetry.execute(
      [:magma, :step, event],
      %{system_time: System.system_time()},
      %{step: step.name, workflow_id: workflow_id(context)}
    )

    :ok
  end

  defp record_error(context, error) do
    Magma.Run.record_error(context, error)

    :ok
  end

  defp workflow_id(%{magma: %Magma.Run{workflow_id: id}}), do: id
  defp workflow_id(_context), do: nil
end
