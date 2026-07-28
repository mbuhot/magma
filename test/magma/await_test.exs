defmodule Magma.AwaitTest do
  use Magma.DataCase, async: false
  use Oban.Testing, repo: Magma.TestRepo

  alias Magma.Store
  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    :ok
  end

  defp drain, do: Oban.drain_queue(queue: :default, with_recursion: true, with_safety: false)

  defp reload(workflow) do
    {:ok, reloaded} = Magma.fetch(workflow.id)
    reloaded
  end

  test "a workflow with nothing to answer it parks, holding no job" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})

    drain()

    assert reload(workflow).status == :waiting
    assert Effects.count(:quote) == 1
    assert Effects.count(:ship) == 0
    assert [] = all_enqueued(worker: Magma.Worker)
  end

  test "a parked workflow records what it is waiting on" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    assert [waiter] = Store.waiters(workflow.id)
    assert waiter.name == "confirm"
    assert waiter.kind == :signal
  end

  test "a signal wakes a parked workflow and it carries on" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})
    drain()

    done = reload(workflow)

    assert done.status == :completed
    assert Effects.count(:ship) == 1
    assert Effects.count(:quote) == 1
  end

  test "the payload a signal carried reaches the step that waited for it" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam", outcome: :approve})
    drain()

    confirmation =
      workflow.id |> Store.standing() |> Enum.find(&(&1.step_label == ":confirmation"))

    assert confirmation.output == %{approver: "sam", outcome: :approve}
  end

  test "a signal that arrives before the wait is reached is still delivered" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "early"})
    drain()

    done = reload(workflow)

    assert done.status == :completed
    assert Effects.count(:ship) == 1
  end

  test "waking a workflow leaves nothing waiting behind it" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})
    drain()

    assert Store.waiters(workflow.id) == []
  end

  test "a signal for a workflow that is not parked waits in its row" do
    {:ok, workflow} = Magma.start(Workflows.Linear, %{order_id: "ord_1"})
    drain()

    {:ok, signal} = Magma.signal(workflow.id, "confirm", :late)

    assert signal.consumed_at == nil
  end

  test "the step that waited is not run again once its signal is recorded" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})
    drain()

    assert Effects.count(:quote) == 1

    labels = workflow.id |> Store.standing() |> Enum.map(& &1.step_label) |> Enum.sort()

    assert labels == [":confirmation", ":quote", ":ship"]
  end
end
