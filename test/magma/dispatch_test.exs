defmodule Magma.DispatchTest do
  use Magma.DataCase, async: false
  use Magma.Testing, repo: Magma.TestRepo

  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    Application.put_env(:magma, :test_rails, %{"EUR" => Workflows.Rail})
    on_exit(fn -> Application.delete_env(:magma, :test_rails) end)
    :ok
  end

  test "a dispatched rail runs as a workflow of its own and its result comes back" do
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})

    run_workflows()

    assert status(spine) == :completed
    assert Effects.count(:rail_send) == 1
    assert {:rail_send, _arguments} = recorded(spine, :rail)
  end

  test "the rail records its own steps, apart from the spine's" do
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})
    run_workflows()

    child_id = Magma.child_id(spine.id, :rail)

    assert tape(spine) == [":quote", ":rail", ":reconcile"]
    assert tape(child_id) == [":send"]
  end

  test "a spine that comes back adopts the child already running rather than starting another" do
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})
    run_workflows()

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => spine.id}})

    assert Effects.count(:rail_send) == 1
    assert Effects.count(:quote) == 1
  end

  test "asking for the same workflow twice is answered with the one already running" do
    id = Magma.child_id("019faae3-0000-7000-8000-000000000000", :twice)

    {:ok, first} = Magma.start(Workflows.Approval, %{order_id: "ord_1"}, workflow_id: id)
    {:ok, second} = Magma.start(Workflows.Approval, %{order_id: "ord_2"}, workflow_id: id)

    assert first.id == second.id
    assert second.inputs == %{order_id: "ord_1"}
    assert length(all_enqueued(worker: Magma.Worker)) == 1
  end

  test "a second caller inserting the same workflow at the same moment is refused" do
    id = Magma.child_id("019faae3-0000-7000-8000-000000000000", :raced)
    attrs = %{id: id, module: Workflows.Approval, inputs: %{order_id: "ord_1"}}

    {:ok, _first} = Magma.Store.start_workflow(attrs)

    assert {:error, error} = Magma.Store.start_workflow(attrs)
    assert Exception.message(error) =~ "already been taken"
  end

  test "the spine names no rail, so changing the routing changes which one runs" do
    defmodule OtherRail do
      @moduledoc false
      use Reactor

      input(:transfer_id)
      step(:send, {Workflows.Effect, name: :other_rail_send})
      return(:send)
    end

    Application.put_env(:magma, :test_rails, %{"USD" => OtherRail})

    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "USD"})
    run_workflows()

    assert status(spine) == :completed
    assert Effects.count(:other_rail_send) == 1
    assert Effects.count(:rail_send) == 0
  end

  test "how long a spine waits for its child comes from the transfer it was started with" do
    {:ok, spine} = Magma.start(Workflows.TimedSpine, %{transfer_id: "t1", window_ms: 90_000})

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => spine.id}})

    %{deadline: deadline} = Magma.Store.waiter(spine.id, "magma.child.:rail")

    assert status(spine) == :waiting
    assert DateTime.diff(deadline, DateTime.utc_now(), :millisecond) in 80_000..90_000
  end

  test "a rail that fails fails the spine that dispatched it" do
    Effects.fail_after(:rail_send, 99)
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})

    run_workflows()

    assert status(spine) == :failed
    assert Effects.count(:reconcile) == 0
  end

  test "a spine still fails when nothing is left to tell it its rail failed" do
    Effects.fail_after(:rail_send, 99)
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})

    attempt(spine.id)
    attempt(Magma.child_id(spine.id, :rail))
    forget_report(spine.id)

    attempt(spine.id)

    assert status(spine) == :failed
    assert Effects.count(:reconcile) == 0
  end

  test "a spine still gets its rail's result when nothing is left to tell it the rail finished" do
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})

    attempt(spine.id)
    attempt(Magma.child_id(spine.id, :rail))
    forget_report(spine.id)

    attempt(spine.id)

    assert status(spine) == :completed
    assert {:rail_send, _arguments} = recorded(spine, :rail)
    assert Effects.count(:rail_send) == 1
  end

  test "a spine that failed because its rail did names the rail and carries its error" do
    Effects.fail_after(:rail_send, 99)
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})

    run_workflows()

    failure = child_failure(spine.id)

    assert failure.workflow_id == Magma.child_id(spine.id, :rail)
    assert failure.module == Workflows.Rail
    assert Exception.message(failure) =~ "rail_send is down"
  end

  test "a spine whose rail died taking its work back still names the rail" do
    Effects.fail_after(:rail_send, 99)
    {:ok, spine} = Magma.start(Workflows.ReversibleSpine, %{transfer_id: "t1"})
    attempt(spine.id)

    child_id = Magma.child_id(spine.id, :rail)
    {:ok, child} = Magma.fetch(child_id)
    {:error, _abandoned} = Magma.Run.run(child)

    assert status(child_id) == :unwinding
    assert Effects.count({:undo, :rail_reserve}) == 1

    attempt(child_id)
    attempt(spine.id)

    assert status(child_id) == :failed
    assert status(spine) == :failed
    assert Effects.count(:reconcile) == 0

    failure = child_failure(spine.id)

    assert failure.workflow_id == child_id
    assert failure.module == Workflows.ReversibleRail
    assert Exception.message(failure) =~ "rail_send is down"
  end

  test "a failure two dispatches down reads through both children to the cause" do
    Effects.fail_after(:leg_body, 99)
    {:ok, corridor} = Magma.start(Workflows.Corridor, %{transfer_id: "t1"})

    run_workflows()

    hop_id = Magma.child_id(corridor.id, :hop)
    leg_id = Magma.child_id(hop_id, :leg)

    outer = child_failure(corridor.id)

    assert status(corridor) == :failed
    assert outer.workflow_id == hop_id
    assert outer.module == Workflows.LegSpine
    assert Exception.message(outer) =~ leg_id
    assert Exception.message(outer) =~ "leg_body is down"

    inner = child_failure(outer.error)

    assert inner.workflow_id == leg_id
    assert inner.module == Workflows.Leg
  end

  test "nothing runs a second time on an attempt after a rail has failed" do
    Effects.fail_after(:rail_send, 99)
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})
    run_workflows()

    attempt(spine.id)

    assert status(spine) == :failed
    assert Effects.count(:quote) == 1
    assert Effects.count(:rail_send) == 1
    assert Effects.count(:reconcile) == 0
  end

  defp attempt(workflow_id) do
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow_id}})
  end

  defp forget_report(spine_id) do
    {:ok, _consumed} =
      spine_id
      |> Magma.Store.pending_signal("magma.child.:rail")
      |> Magma.Store.consume_signal()

    :ok
  end
end
