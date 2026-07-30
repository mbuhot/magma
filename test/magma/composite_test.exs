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

  describe "a branch that waits" do
    test "a workflow whose chosen branch waits for a signal stops until one arrives" do
      {:ok, workflow} = Magma.start(Workflows.BranchedApproval, %{amount: 500})

      run_workflows()

      assert status(workflow) == :waiting
      assert Effects.count(:large) == 0

      {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})

      run_workflows()

      assert status(workflow) == :completed
      assert Effects.count(:large) == 1
      assert recorded(workflow, :confirmation) == %{approver: "sam"}
    end

    test "a branch that waited is not run again on a later attempt" do
      {:ok, workflow} = Magma.start(Workflows.BranchedApproval, %{amount: 500})
      run_workflows()
      {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})
      run_workflows()

      Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

      assert Effects.count(:large) == 1
      assert status(workflow) == :completed
    end
  end

  describe "a branch that runs another workflow" do
    setup do
      Application.put_env(:magma, :test_rails, %{"EUR" => Workflows.Rail})
      on_exit(fn -> Application.delete_env(:magma, :test_rails) end)
      :ok
    end

    test "a workflow whose chosen branch runs a child stops until the child reports" do
      {:ok, workflow} =
        Magma.start(Workflows.BranchedDispatch, %{amount: 500, transfer_id: "t1"})

      run_workflows(with_recursion: false)

      assert status(workflow) == :waiting
      assert Effects.count(:rail_send) == 0
      assert status(Magma.child_id(workflow.id, :rail)) == :pending

      run_workflows()

      assert status(workflow) == :completed
      assert Effects.count(:rail_send) == 1
      assert Effects.count(:reconcile) == 1
      assert tape(Magma.child_id(workflow.id, :rail)) == [":send"]
    end

    test "a branch that ran a child does not run it again on a later attempt" do
      {:ok, workflow} =
        Magma.start(Workflows.BranchedDispatch, %{amount: 500, transfer_id: "t1"})

      run_workflows()

      Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

      assert Effects.count(:rail_send) == 1
      assert Effects.count(:reconcile) == 1
      assert status(workflow) == :completed
    end
  end

  describe "each element of a map waiting" do
    test "every element waits for a signal of its own before the map finishes" do
      {:ok, workflow} = Magma.start(Workflows.MappedApproval, %{order_ids: ["a", "b"]})

      run_workflows()

      assert status(workflow) == :waiting
      assert Effects.count(:charge) == 0

      {:ok, _first} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})

      run_workflows()

      assert status(workflow) == :waiting
      assert Effects.count(:charge) == 1

      {:ok, _second} = Magma.signal(workflow.id, "confirm", %{approver: "kim"})

      run_workflows()

      assert status(workflow) == :completed
      assert Effects.count(:charge) == 2
      assert Effects.count(:total) == 1

      assert recorded(workflow, {Reactor.Step.Map, :approvals, :confirmation, 0}) == %{
               approver: "sam"
             }

      assert recorded(workflow, {Reactor.Step.Map, :approvals, :confirmation, 1}) == %{
               approver: "kim"
             }
    end

    test "elements that already waited are not run again on a later attempt" do
      {:ok, workflow} = Magma.start(Workflows.MappedApproval, %{order_ids: ["a", "b"]})
      run_workflows()
      {:ok, _first} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})
      {:ok, _second} = Magma.signal(workflow.id, "confirm", %{approver: "kim"})
      run_workflows()

      Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

      assert Effects.count(:charge) == 2
      assert Effects.count(:total) == 1
    end
  end

  describe "each element of a map running another workflow" do
    setup do
      Application.put_env(:magma, :test_rails, %{"EUR" => Workflows.Rail})
      on_exit(fn -> Application.delete_env(:magma, :test_rails) end)
      :ok
    end

    test "every element runs a child of its own and the map collects what they returned" do
      {:ok, workflow} = Magma.start(Workflows.MappedDispatch, %{transfer_ids: ["t1", "t2"]})

      run_workflows()

      assert status(workflow) == :completed
      assert Effects.count(:rail_send) == 2
      assert Effects.count(:settle) == 1

      first = Magma.child_id(workflow.id, {Reactor.Step.Map, :rails, :rail, 0})
      second = Magma.child_id(workflow.id, {Reactor.Step.Map, :rails, :rail, 1})

      assert first != second
      assert tape(first) == [":send"]
      assert tape(second) == [":send"]
    end

    test "elements that already ran a child do not run another on a later attempt" do
      {:ok, workflow} = Magma.start(Workflows.MappedDispatch, %{transfer_ids: ["t1", "t2"]})
      run_workflows()

      Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

      assert Effects.count(:rail_send) == 2
      assert Effects.count(:settle) == 1
    end
  end

  test "the names a map generates are the same on every attempt" do
    {:ok, first} = Magma.start(Workflows.Mapped, %{order_ids: ["a", "b"]})
    run_workflows()

    before = tape(first) |> Enum.sort()

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => first.id}})

    assert tape(first) |> Enum.sort() == before
  end
end
