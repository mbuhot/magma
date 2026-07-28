defmodule Magma.RetentionTest do
  use Magma.DataCase, async: false
  use Magma.Testing, repo: Magma.TestRepo

  alias Magma.Store
  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    Application.delete_env(:magma, :retention)
    on_exit(fn -> Application.delete_env(:magma, :retention) end)
    :ok
  end

  defp finished(module) do
    {:ok, workflow} = Magma.start(module, %{order_id: "ord_1"})
    run_workflows()
    workflow
  end

  test "nothing is kept for a set time unless something says so" do
    assert Magma.Retention.for_workflow(Workflows.Linear) == :infinity
  end

  test "a workflow's own retention is what applies to it" do
    Application.put_env(:magma, :retention, 60_000)

    assert Magma.Retention.for_workflow(Workflows.Ephemeral) == 1
    assert Magma.Retention.for_workflow(Workflows.Kept) == :infinity
    assert Magma.Retention.for_workflow(Workflows.Linear) == 60_000
  end

  test "a workflow that has outlived its retention is deleted" do
    workflow = finished(Workflows.Ephemeral)

    assert {:ok, 1} = Magma.prune()
    assert status(workflow) == nil
  end

  test "everything belonging to a pruned workflow goes with it" do
    workflow = finished(Workflows.Ephemeral)

    assert Store.standing(workflow.id) != []

    {:ok, 1} = Magma.prune()

    assert Store.standing(workflow.id) == []
    assert Store.waiters(workflow.id) == []
  end

  test "a workflow kept forever is never pruned" do
    workflow = finished(Workflows.Kept)

    assert {:ok, 0} = Magma.prune()
    assert status(workflow) == :completed
  end

  test "a workflow still running is left alone, however old" do
    {:ok, workflow} = Magma.start(Workflows.Ephemeral, %{order_id: "ord_1"})

    assert {:ok, 0} = Magma.prune()
    assert status(workflow) == :pending
  end

  test "a workflow younger than its retention is left alone" do
    Application.put_env(:magma, :retention, :timer.hours(1))
    workflow = finished(Workflows.Linear)

    assert {:ok, 0} = Magma.prune()
    assert status(workflow) == :completed
  end

  test "a pass takes no more than it was asked to" do
    for _each <- 1..3, do: finished(Workflows.Ephemeral)

    assert {:ok, 2} = Magma.prune(limit: 2)
    assert {:ok, 1} = Magma.prune(limit: 2)
    assert {:ok, 0} = Magma.prune(limit: 2)
  end

  test "the pruner worker reports what it deleted" do
    finished(Workflows.Ephemeral)

    assert {:ok, %{pruned: 1}} = Magma.Pruner.perform(%Oban.Job{args: %{}})
  end
end
