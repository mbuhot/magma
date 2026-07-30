defmodule Magma.StoreTest do
  use Magma.DataCase, async: true

  alias Magma.Store
  alias Magma.Test.Store, as: TestStore

  test "finds the resource playing each role in the configured domain" do
    assert Store.resource(:workflow) == TestStore.Workflow
    assert Store.resource(:checkpoint) == TestStore.Checkpoint
    assert Store.resource(:signal) == TestStore.Signal
    assert Store.resource(:waiter) == TestStore.Waiter
  end

  test "names the role and the domain when nothing plays it" do
    defmodule EmptyDomain do
      @moduledoc false
      use Ash.Domain, validate_config_inclusion?: false

      resources do
      end
    end

    error = assert_raise RuntimeError, fn -> Store.resource(:workflow, EmptyDomain) end
    message = error.message

    assert message =~ "workflow"
    assert message =~ inspect(EmptyDomain)
    assert message =~ "Magma.Resource.Workflow"
  end

  test "reports the repo the store writes through" do
    assert Store.repo() == Magma.TestRepo
  end

  defp workflow do
    {:ok, workflow} = Store.start_workflow(%{module: TestStore.Workflow, inputs: %{}})
    workflow
  end

  test "a signal answers only the first of the attempts reaching for it" do
    workflow = workflow()
    {:ok, signal} = Store.deliver_signal(workflow.id, "confirm", :yes)

    assert {:ok, _consumed} = Store.consume_signal(signal)
    assert Store.consume_signal(signal) == :taken
  end

  test "clearing a wait another attempt has already cleared is no error" do
    workflow = workflow()
    {:ok, _waiter} = Store.park(workflow.id, "confirm", :signal, nil)

    assert Store.release(workflow.id, "confirm") == :ok
    assert Store.release_all(workflow.id) == :ok
    assert Store.waiters(workflow.id) == []
  end

  test "a second recording of a step answers with the one that stands" do
    workflow = workflow()

    {:ok, stands} = Store.record(workflow.id, :charge, {:ok, :first})
    {:ok, adopted} = Store.record(workflow.id, :charge, {:ok, :second})

    assert adopted.id == stands.id
    assert adopted.output == {:ok, :first}
    assert length(Store.standing(workflow.id)) == 1
  end
end
