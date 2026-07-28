defmodule Magma.CompositeTest do
  use Magma.DataCase, async: false
  use Magma.Testing, repo: Magma.TestRepo

  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    :ok
  end

  test "each element of a map records on its own" do
    {:ok, workflow} = Magma.start(Workflows.Mapped, %{order_ids: ["a", "b", "c"]})

    run_workflows()

    assert status(workflow) == :completed
    assert Effects.count(:charge) == 3
    assert length(tape(workflow)) > 3
  end

  test "a map re-runs no element that already recorded" do
    {:ok, workflow} = Magma.start(Workflows.Mapped, %{order_ids: ["a", "b", "c"]})
    run_workflows()

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:charge) == 3
  end

  test "the branch a switch took is what records, and the other is not run" do
    {:ok, workflow} = Magma.start(Workflows.Branching, %{amount: 500})

    run_workflows()

    assert status(workflow) == :completed
    assert Effects.count(:large) == 1
    assert Effects.count(:small) == 0
  end

  test "a switch takes the same branch on a later attempt" do
    {:ok, workflow} = Magma.start(Workflows.Branching, %{amount: 10})
    run_workflows()

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:small) == 1
    assert Effects.count(:large) == 0
  end

  test "the names a map generates are the same on every attempt" do
    {:ok, first} = Magma.start(Workflows.Mapped, %{order_ids: ["a", "b"]})
    run_workflows()

    before = tape(first) |> Enum.sort()

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => first.id}})

    assert tape(first) |> Enum.sort() == before
  end
end
