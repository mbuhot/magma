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

  test "two spines racing to dispatch the same child start one of it" do
    id = Magma.child_id("019faae3-0000-7000-8000-000000000000", :raced)

    started =
      for _each <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Magma.TestRepo, self(), self())
          Magma.start(Workflows.Approval, %{order_id: "ord_1"}, workflow_id: id)
        end)
      end
      |> Task.await_many(5_000)

    assert [{:ok, one}, {:ok, two}] = started
    assert one.id == two.id
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

  test "a rail that fails fails the spine that dispatched it" do
    Effects.fail_after(:rail_send, 99)
    {:ok, spine} = Magma.start(Workflows.Spine, %{transfer_id: "t1", currency: "EUR"})

    run_workflows()

    assert status(spine) == :failed
    assert Effects.count(:reconcile) == 0
  end
end
