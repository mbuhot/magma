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

  test "the step before a poll is not run again when the workflow comes back" do
    {:ok, workflow} = Magma.start(Workflows.Polling, %{order_id: "ord_1"})

    Oban.drain_queue(queue: :default, with_safety: false)
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:quote) == 1
  end
end
