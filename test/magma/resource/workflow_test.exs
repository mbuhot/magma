defmodule Magma.Resource.WorkflowTest do
  use Magma.DataCase, async: true

  alias Magma.Test.Store.Workflow

  defp start(attrs) do
    defaults = %{module: Magma.Test.Store.Workflow, inputs: %{}}

    Workflow
    |> Ash.Changeset.for_create(:start, Map.merge(defaults, attrs))
    |> Ash.create()
  end

  test "a started workflow is pending and has no result yet" do
    {:ok, workflow} = start(%{})

    assert workflow.status == :pending
    assert workflow.result == nil
    assert workflow.error == nil
  end

  test "the inputs a workflow was started with come back as they went in" do
    {:ok, workflow} = start(%{inputs: %{order_id: "ord_1", amount: Decimal.new("49.99")}})
    {:ok, reloaded} = Ash.get(Workflow, workflow.id)

    assert reloaded.inputs == %{order_id: "ord_1", amount: Decimal.new("49.99")}
  end

  test "the actor and tenant a workflow was started with come back as they went in" do
    {:ok, workflow} = start(%{actor: %{id: 7, roles: [:admin]}, tenant: "acme"})
    {:ok, reloaded} = Ash.get(Workflow, workflow.id)

    assert reloaded.actor == %{id: 7, roles: [:admin]}
    assert reloaded.tenant == "acme"
  end

  test "a workflow started without an actor or tenant has neither" do
    {:ok, workflow} = start(%{})

    assert workflow.actor == nil
    assert workflow.tenant == nil
  end

  test "the module a workflow runs comes back as a module" do
    {:ok, workflow} = start(%{module: Magma.Test.Store.Workflow})
    {:ok, reloaded} = Ash.get(Workflow, workflow.id)

    assert reloaded.module == Magma.Test.Store.Workflow
  end

  test "a workflow cannot be started without a module" do
    assert {:error, %Ash.Error.Invalid{}} =
             Workflow
             |> Ash.Changeset.for_create(:start, %{inputs: %{}})
             |> Ash.create()
  end

  test "completing a workflow records its result" do
    {:ok, workflow} = start(%{})

    {:ok, completed} =
      workflow
      |> Ash.Changeset.for_update(:complete, %{result: {:ok, :shipped}})
      |> Ash.update()

    assert completed.status == :completed
    assert completed.result == {:ok, :shipped}
  end

  test "failing a workflow records its error" do
    {:ok, workflow} = start(%{})

    {:ok, failed} =
      workflow
      |> Ash.Changeset.for_update(:fail, %{error: %RuntimeError{message: "provider down"}})
      |> Ash.update()

    assert failed.status == :failed
    assert failed.error == %RuntimeError{message: "provider down"}
  end

  test "a workflow can be moved to any state it can park in" do
    for status <- [:waiting, :polling, :unwinding] do
      {:ok, workflow} = start(%{})

      {:ok, parked} =
        workflow
        |> Ash.Changeset.for_update(:set_status, %{status: status})
        |> Ash.update()

      assert parked.status == status
    end
  end
end
