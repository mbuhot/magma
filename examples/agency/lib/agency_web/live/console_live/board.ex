defmodule AgencyWeb.ConsoleLive.Board do
  @moduledoc """
  Every magma workflow the agency has started, the dispatch tree between them, and one
  workflow's checkpoints, signals and waits read back for inspection.
  """

  require Ash.Query

  alias Agency.Magma.Signal
  alias Agency.Magma.Workflow
  alias Magma.Store

  @doc "Every workflow the agency has started, most recently started first."
  @spec workflows() :: [Ash.Resource.record()]
  def workflows do
    Workflow |> Ash.read!() |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc "Every status a workflow can be in, for the filter."
  @spec statuses() :: [atom()]
  def statuses, do: Magma.Status.values()

  @doc "The workflows in the given status, or all of them for `:all`."
  @spec filtered(:all | atom(), [Ash.Resource.record()]) :: [Ash.Resource.record()]
  def filtered(:all, workflows), do: workflows
  def filtered(status, workflows), do: Enum.filter(workflows, &(&1.status == status))

  @doc "The Oban queue a workflow's module runs its job on."
  @spec queue(module()) :: atom()
  def queue(module), do: Spark.Dsl.Extension.get_opt(module, [:magma], :queue, :default)

  @doc """
  The dispatch tree: every workflow the agency started directly paired with the workflows it
  dispatched, nested to whatever depth the chain runs.
  """
  @spec tree([Ash.Resource.record()]) :: [{Ash.Resource.record(), list()}]
  def tree(workflows) do
    by_parent = Enum.group_by(workflows, & &1.parent_workflow_id)

    workflows
    |> Enum.filter(&is_nil(&1.parent_workflow_id))
    |> sorted_by_start()
    |> Enum.map(&branch(&1, by_parent))
  end

  defp branch(workflow, by_parent) do
    children =
      by_parent
      |> Map.get(workflow.id, [])
      |> sorted_by_start()
      |> Enum.map(&branch(&1, by_parent))

    {workflow, children}
  end

  defp sorted_by_start(workflows), do: Enum.sort_by(workflows, & &1.inserted_at, DateTime)

  @doc """
  One workflow's checkpoints in completion order, the signals it has been sent, and what it is
  presently parked on. `nil` if no such workflow has been started.
  """
  @spec detail(String.t()) :: map() | nil
  def detail(workflow_id) do
    case Store.get_workflow(workflow_id) do
      {:ok, nil} ->
        nil

      {:ok, workflow} ->
        %{
          workflow: workflow,
          parent: workflow.parent_workflow_id && fetch_workflow(workflow.parent_workflow_id),
          checkpoints: workflow_id |> Store.standing() |> Enum.sort_by(& &1.id),
          signals: signals_for(workflow_id),
          waiters: Store.waiters(workflow_id)
        }
    end
  end

  defp fetch_workflow(workflow_id) do
    case Store.get_workflow(workflow_id) do
      {:ok, workflow} -> workflow
      {:error, _reason} -> nil
    end
  end

  defp signals_for(workflow_id) do
    Signal
    |> Ash.Query.filter(workflow_id == ^workflow_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  @doc "A module's last segment, for a compact label."
  @spec short(module()) :: String.t()
  def short(module), do: module |> Module.split() |> List.last()

  @doc "How long a workflow has stood in its current status, in words."
  @spec in_status(Ash.Resource.record(), DateTime.t()) :: String.t()
  def in_status(workflow, now \\ DateTime.utc_now()) do
    now |> DateTime.diff(workflow.updated_at) |> duration_words()
  end

  @doc "A moment as words relative to a deadline, for a parked workflow's wait."
  @spec deadline_words(DateTime.t(), DateTime.t()) :: String.t()
  def deadline_words(deadline, now \\ DateTime.utc_now()) do
    seconds = DateTime.diff(deadline, now)

    if seconds >= 0,
      do: "due in #{duration_words(seconds)}",
      else: "overdue by #{duration_words(-seconds)}"
  end

  defp duration_words(seconds) when seconds < 60, do: "#{seconds}s"
  defp duration_words(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp duration_words(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)}h"
  defp duration_words(seconds), do: "#{div(seconds, 86_400)}d"

  @doc "A large checkpoint output or signal payload, previewed for a table cell."
  @spec preview(term()) :: String.t()
  def preview(term) do
    rendered = inspect(term, pretty: true, limit: 20, printable_limit: 200)

    if String.length(rendered) > 160,
      do: String.slice(rendered, 0, 160) <> "…",
      else: rendered
  end

  @doc "A checkpoint output or signal payload in full, for expansion."
  @spec full(term()) :: String.t()
  def full(term), do: inspect(term, pretty: true, limit: :infinity, printable_limit: :infinity)
end
