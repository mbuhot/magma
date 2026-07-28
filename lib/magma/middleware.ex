defmodule Magma.Middleware do
  @moduledoc """
  Observes a durable run.

  Its `event/3` can only report, so the checkpoint write lives in `Magma.Checkpointed`, where
  a failure to write can fail the step.
  """

  use Reactor.Middleware

  @impl true
  def event({:run_complete, _result}, step, context) do
    telemetry(:step_complete, step, context)
  end

  def event({:run_error, _errors}, step, context) do
    telemetry(:step_error, step, context)
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

  defp workflow_id(%{magma: %Magma.Run{workflow_id: id}}), do: id
  defp workflow_id(_context), do: nil
end
