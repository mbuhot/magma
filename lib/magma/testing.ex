defmodule Magma.Testing do
  @moduledoc """
  Helpers for testing durable workflows.

      use Magma.Testing, repo: MyApp.Repo

      test "a payout survives its worker dying" do
        {:ok, workflow} = Magma.start(MyApp.Payout, %{transfer_id: id})

        run_workflows()

        assert tape(workflow) == [":quote", ":debit", ":transfer"]
      end

  `tape/1` is the checkpoint sequence in the order the steps completed. Asserting on it pins
  the shape of a workflow, so an edit that adds, drops or reorders a step says so.
  """

  alias Magma.Store

  defmacro __using__(options) do
    quote do
      use Oban.Testing, unquote(options)

      import Magma.Testing
    end
  end

  @doc "Runs every job that is ready, including ones started while draining."
  @spec run_workflows(keyword()) :: term()
  def run_workflows(options \\ []) do
    options
    |> Keyword.put_new(:queue, :default)
    |> Keyword.put_new(:with_recursion, true)
    |> Keyword.put_new(:with_safety, false)
    |> Oban.drain_queue()
  end

  @doc "The steps a workflow has recorded, in the order they completed."
  @spec tape(Ash.Resource.record() | String.t()) :: [String.t()]
  def tape(%{id: workflow_id}), do: tape(workflow_id)

  def tape(workflow_id) when is_binary(workflow_id) do
    workflow_id
    |> Store.standing()
    |> Enum.sort_by(& &1.id)
    |> Enum.map(& &1.step_label)
  end

  @doc "What a named step recorded, or `nil` if it has not run or was taken back."
  @spec recorded(Ash.Resource.record() | String.t(), term()) :: term()
  def recorded(%{id: workflow_id}, name), do: recorded(workflow_id, name)

  def recorded(workflow_id, name) when is_binary(workflow_id) do
    key = Magma.Key.for(name)

    workflow_id
    |> Store.standing()
    |> Enum.find(&(&1.step_key == key))
    |> case do
      nil -> nil
      checkpoint -> checkpoint.output
    end
  end

  @doc "The status the store last recorded for a workflow."
  @spec status(Ash.Resource.record() | String.t()) :: atom() | nil
  def status(%{id: workflow_id}), do: status(workflow_id)

  def status(workflow_id) when is_binary(workflow_id) do
    case Store.get_workflow(workflow_id) do
      {:ok, nil} -> nil
      {:ok, workflow} -> workflow.status
      _error -> nil
    end
  end
end
