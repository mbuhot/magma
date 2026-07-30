defmodule Magma.PollTest do
  use Magma.DataCase, async: false
  use Oban.Testing, repo: Magma.TestRepo

  alias Magma.Store
  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    :ok
  end

  defp reload(workflow) do
    {:ok, reloaded} = Magma.fetch(workflow.id)
    reloaded
  end

  test "a condition that does not hold yet parks the workflow for another look" do
    {:ok, workflow} = Magma.start(Workflows.Polling, %{order_id: "ord_1"})

    Oban.drain_queue(queue: :default, with_safety: false)

    assert reload(workflow).status == :polling
    assert Effects.count(:settlement_check) == 1
    assert [waiter] = Store.waiters(workflow.id)
    assert waiter.kind == :poll
  end

  test "a workflow finishes on the check that satisfies its condition" do
    {:ok, workflow} = Magma.start(Workflows.Polling, %{order_id: "ord_1"})

    Oban.drain_queue(queue: :default, with_safety: false)
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    done = reload(workflow)

    assert done.status == :completed
    assert done.result == :settled
    assert Effects.count(:settlement_check) == 2
  end

  test "a workflow between polls can be brought back to look again straight away" do
    {:ok, workflow} = Magma.start(Workflows.Polling, %{order_id: "ord_1"})

    Oban.drain_queue(queue: :default, with_safety: false)

    assert reload(workflow).status == :polling

    :ok = Magma.wake(workflow.id)

    Oban.drain_queue(queue: :default, with_safety: false)

    assert reload(workflow).status == :completed
    assert Effects.count(:settlement_check) == 2
  end

  test "a poll beside a wait still holds the job that brings the workflow back" do
    {:ok, workflow} = Magma.start(Workflows.Watched, %{order_id: "ord_1"})

    Oban.drain_queue(queue: :default, with_safety: false)

    kinds = workflow.id |> Store.waiters() |> Enum.map(& &1.kind) |> Enum.sort()

    assert reload(workflow).status == :polling
    assert kinds == [:poll, :signal]
  end

  test "the step before a poll is not run again when the workflow comes back" do
    {:ok, workflow} = Magma.start(Workflows.Polling, %{order_id: "ord_1"})

    Oban.drain_queue(queue: :default, with_safety: false)
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:quote) == 1
  end
end
