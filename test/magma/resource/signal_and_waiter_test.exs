defmodule Magma.Resource.SignalAndWaiterTest do
  use Magma.DataCase, async: true

  alias Magma.Test.Store.Signal
  alias Magma.Test.Store.Waiter
  alias Magma.Test.Store.Workflow

  setup do
    {:ok, workflow} =
      Workflow
      |> Ash.Changeset.for_create(:start, %{module: Workflow, inputs: %{}})
      |> Ash.create()

    %{workflow: workflow}
  end

  defp deliver(workflow, attrs) do
    defaults = %{workflow_id: workflow.id, name: "confirm"}

    Signal
    |> Ash.Changeset.for_create(:deliver, Map.merge(defaults, attrs))
    |> Ash.create()
  end

  defp park(workflow, attrs) do
    defaults = %{workflow_id: workflow.id, name: "confirm"}

    Waiter
    |> Ash.Changeset.for_create(:park, Map.merge(defaults, attrs))
    |> Ash.create()
  end

  test "a delivered payload comes back as it went in", %{workflow: workflow} do
    {:ok, signal} = deliver(workflow, %{payload: %{outcome: :approve, approver: "sam"}})
    {:ok, reloaded} = Ash.get(Signal, signal.id)

    assert reloaded.payload == %{outcome: :approve, approver: "sam"}
  end

  test "a delivered signal is unconsumed until something takes it", %{workflow: workflow} do
    {:ok, signal} = deliver(workflow, %{payload: :approve})

    assert signal.consumed_at == nil

    {:ok, consumed} =
      signal
      |> Ash.Changeset.for_update(:consume, %{})
      |> Ash.update()

    assert %DateTime{} = consumed.consumed_at
  end

  test "the same name can be delivered more than once", %{workflow: workflow} do
    {:ok, first} = deliver(workflow, %{payload: :one})
    {:ok, second} = deliver(workflow, %{payload: :two})

    refute first.id == second.id
  end

  test "parking records the deadline the wait ends at", %{workflow: workflow} do
    deadline = DateTime.add(DateTime.utc_now(), 3600, :second)
    {:ok, waiter} = park(workflow, %{deadline: deadline})

    assert DateTime.compare(waiter.deadline, deadline) == :eq
  end

  test "parking twice on one name keeps a single wait", %{workflow: workflow} do
    {:ok, first} = park(workflow, %{})
    {:ok, second} = park(workflow, %{})

    assert first.id == second.id
  end

  test "a workflow can wait on two names at once", %{workflow: workflow} do
    {:ok, _confirm} = park(workflow, %{name: "confirm"})
    {:ok, _webhook} = park(workflow, %{name: "webhook"})

    assert Waiter |> Ash.read!() |> length() == 2
  end

  test "releasing a wait removes it", %{workflow: workflow} do
    {:ok, waiter} = park(workflow, %{})

    :ok = Ash.destroy!(waiter)

    assert Waiter |> Ash.read!() == []
  end
end
