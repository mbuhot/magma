defmodule Magma.Worker do
  @moduledoc """
  The one Oban worker every durable workflow runs under.

  It carries a workflow id and nothing else. Everything about the run — the module, the
  inputs, the actor, what has already finished — is read from the store on each attempt.
  """

  use Oban.Worker, max_attempts: 20

  alias Magma.Run
  alias Magma.Store

  @impl true
  def perform(%Oban.Job{args: %{"workflow_id" => workflow_id}}) do
    case Store.get_workflow(workflow_id) do
      {:ok, nil} -> {:cancel, "magma has no workflow #{workflow_id}"}
      {:ok, workflow} -> run(workflow)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run(%{status: status} = workflow) when status in [:completed, :failed, :cancelled] do
    {:cancel, "workflow #{workflow.id} already ended as #{status}"}
  end

  defp run(%{status: :unwinding} = workflow), do: unwind(workflow, :fail)
  defp run(%{status: :cancelling} = workflow), do: unwind(workflow, :cancelled)

  defp run(workflow) do
    workflow
    |> Run.run()
    |> outcome(workflow)
  end

  # A rollback already under way never rolls forward again. It picks up from the marks and
  # ends the workflow once nothing is left standing.
  defp unwind(workflow, ending) do
    case Magma.Unwind.run(workflow) do
      {:ok, []} ->
        {:ok, _ended} = Store.update_workflow(workflow, ending, %{})
        :ok

      {:error, errors} ->
        {:cancel, errors}
    end
  end

  defp outcome({:ok, result}, workflow) do
    {:ok, completed} = Store.update_workflow(workflow, :complete, %{result: result})
    :ok = Magma.Api.report_to_parent(completed, {:ok, result})
    :ok
  end

  # A halted run has already written what it is parked on, so the worker reads that from
  # committed state rather than from the halt.
  defp outcome({:halted, _reactor}, workflow) do
    case Store.waiters(workflow.id) do
      [] ->
        {:ok, _waiting} = Store.update_workflow(workflow, :set_status, %{status: :waiting})
        :ok

      waiters ->
        park(workflow, waiters)
    end
  end

  defp outcome({:error, error}, workflow) do
    {:ok, current} = Store.get_workflow(workflow.id)
    {:ok, failed} = Store.update_workflow(current, :fail, %{error: error})
    :ok = Magma.Api.report_to_parent(failed, {:error, error})
    {:cancel, error}
  end

  defp park(workflow, waiters) do
    case Enum.filter(waiters, &(&1.kind == :poll)) do
      [] ->
        {:ok, _waiting} = Store.update_workflow(workflow, :set_status, %{status: :waiting})
        :ok

      polls ->
        {:ok, _polling} = Store.update_workflow(workflow, :set_status, %{status: :polling})
        {:snooze, soonest(polls)}
    end
  end

  defp soonest(polls) do
    polls
    |> Enum.map(&seconds_until(&1.deadline))
    |> Enum.min()
    |> max(1)
  end

  defp seconds_until(nil), do: 30

  defp seconds_until(deadline) do
    DateTime.utc_now() |> DateTime.diff(deadline) |> abs()
  end
end
