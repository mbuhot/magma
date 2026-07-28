defmodule Magma.Retention do
  @moduledoc """
  How long a finished workflow's rows are kept, and the pruning that enforces it.

  Retention is read from the workflow itself first, so a payout audited for seven years and a
  webhook kept for an hour live in the same system:

      magma do
        retention :timer.hours(24 * 365 * 7)
      end

  Without one on the workflow it falls back to `config :magma, retention: ...`, and to
  `:infinity` if neither is set. Nothing is deleted by default.

  Only a workflow that has ended is ever pruned, and its checkpoints, signals and waiters go
  with it.
  """

  alias Magma.Store

  require Ash.Query

  @doc "How long this workflow's rows are kept once it ends."
  @spec for_workflow(module()) :: pos_integer() | :infinity
  def for_workflow(module) do
    declared(module) || Application.get_env(:magma, :retention) || :infinity
  end

  defp declared(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0) do
      Spark.Dsl.Extension.get_opt(module, [:magma], :retention, nil)
    end
  end

  @doc """
  Deletes the workflows that have outlived their retention, and everything belonging to them.

  Returns how many went. `:limit` caps one pass so a long backlog is worked through over
  several rather than in one transaction.

      Magma.Retention.prune(limit: 500)
  """
  @spec prune(keyword()) :: {:ok, non_neg_integer()}
  def prune(options \\ []) do
    limit = Keyword.get(options, :limit, 1_000)
    now = Keyword.get(options, :now, DateTime.utc_now())

    expired =
      :workflow
      |> Store.resource()
      |> Ash.Query.filter(status in [:completed, :failed, :cancelled])
      |> Ash.Query.sort(updated_at: :asc)
      |> Ash.Query.limit(limit)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&expired?(&1, now))

    Enum.each(expired, &delete/1)

    {:ok, length(expired)}
  end

  defp expired?(workflow, now) do
    case for_workflow(workflow.module) do
      :infinity -> false
      ms -> DateTime.diff(now, workflow.updated_at, :millisecond) >= ms
    end
  end

  # The children go first, so a pruning run interrupted part way leaves a workflow whose rows
  # are gone rather than rows whose workflow is.
  defp delete(workflow) do
    for role <- [:checkpoint, :signal, :waiter] do
      role
      |> Store.resource()
      |> Ash.Query.filter(workflow_id == ^workflow.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    Ash.destroy!(workflow, authorize?: false)
  end
end
