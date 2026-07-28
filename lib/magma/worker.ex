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
    {:ok, _completed} = Store.update_workflow(workflow, :complete, %{result: result})
    :ok
  end

  defp outcome({:error, error}, workflow) do
    {:ok, current} = Store.get_workflow(workflow.id)
    {:ok, _failed} = Store.update_workflow(current, :fail, %{error: error})
    {:cancel, error}
  end
end
