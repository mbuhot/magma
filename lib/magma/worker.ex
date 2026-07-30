defmodule Magma.Worker do
  @moduledoc """
  The one Oban worker every durable workflow runs under.

  It carries a workflow id and nothing else. Everything about the run — the module, the
  inputs, the actor, what has already finished — is read from the store on each attempt.
  """

  use Oban.Worker, max_attempts: 20

  alias Magma.Run
  alias Magma.Store

  @terminal [:completed, :failed, :cancelled]

  @impl true
  def perform(%Oban.Job{args: %{"workflow_id" => workflow_id}}) do
    case Store.get_workflow(workflow_id) do
      {:ok, nil} -> {:cancel, "magma has no workflow #{workflow_id}"}
      {:ok, workflow} -> run(workflow)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run(%{status: status} = workflow) when status in @terminal, do: already_ended(workflow)

  defp run(%{status: :unwinding} = workflow), do: unwind(workflow, :fail)
  defp run(%{status: :cancelling} = workflow), do: unwind(workflow, :cancelled)

  defp run(workflow) do
    workflow
    |> Run.run()
    |> outcome(workflow)
  end

  # A rollback already under way never rolls forward again. It picks up from the marks and
  # ends the workflow once nothing is left standing. The failure that started the rollback was
  # written before it began, so the ending carries it and the parent is told the same thing the
  # ordinary failure path would have told it.
  defp unwind(workflow, ending) do
    case Magma.Unwind.run(workflow) do
      {:ok, _unresolved} ->
        {:ok, ended} = Store.update_workflow(workflow, ending, %{})
        :ok = Store.release_all(ended.id)
        :ok = Magma.Api.report_to_parent(ended, {:error, ended.error || ended.status})
        :ok

      {:error, errors} ->
        {:cancel, errors}
    end
  end

  defp outcome({:ok, result}, workflow) do
    case reload(workflow) do
      {:ended, ended} -> already_ended(ended)
      {:ok, current} -> complete(current, result)
    end
  end

  # A halted run has already written what it is parked on, so the worker reads that from
  # committed state rather than from the halt.
  defp outcome({:halted, _reactor}, workflow) do
    case reload(workflow) do
      {:ended, ended} -> already_ended(ended)
      {:ok, current} -> park(current, Store.waiters(current.id))
    end
  end

  defp outcome({:error, error}, workflow) do
    case reload(workflow) do
      {:ended, ended} -> already_ended(ended)
      {:ok, current} -> fail(current, error)
    end
  end

  defp complete(workflow, result) do
    {:ok, completed} = Store.update_workflow(workflow, :complete, %{result: result})
    :ok = Store.release_all(completed.id)
    :ok = Magma.Api.report_to_parent(completed, {:ok, result})
    :ok
  end

  defp fail(workflow, error) do
    {:ok, failed} = Store.update_workflow(workflow, :fail, %{error: error})
    :ok = Store.release_all(failed.id)
    :ok = Magma.Api.report_to_parent(failed, {:error, error})
    {:cancel, error}
  end

  # An ending stands. A workflow that has already had its say is not moved by an attempt of it
  # that was still running, so a halt cannot park a run that another attempt has failed.
  defp reload(workflow) do
    case Store.get_workflow(workflow.id) do
      {:ok, %{status: status} = current} when status in @terminal -> {:ended, current}
      {:ok, nil} -> {:ended, workflow}
      {:ok, current} -> {:ok, current}
      {:error, _reason} -> {:ok, workflow}
    end
  end

  # An attempt that lost a race can leave the workflow parked on a signal another attempt has
  # already taken, so an ended workflow clears whatever it is holding on its way out.
  defp already_ended(%{id: id, status: status}) do
    :ok = Store.release_all(id)
    {:cancel, "workflow #{id} already ended as #{status}"}
  end

  defp park(workflow, waiters) do
    case Enum.filter(waiters, &(&1.kind == :poll)) do
      [] ->
        {:ok, _waiting} = Magma.Api.park_or_resume(workflow, waiters)
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
