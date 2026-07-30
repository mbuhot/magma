defmodule Magma.UnwindTest do
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

  test "a failing run takes back the steps that had finished" do
    Effects.fail_after(:charge, 99)
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})

    drain()

    assert Effects.count({:undo, :quote}) == 1
    assert reload(workflow).status in [:failed, :unwinding]
  end

  test "a workflow that has taken anything back never runs forward again" do
    Effects.fail_after(:charge, 99)
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})

    drain()

    charges = Effects.count(:charge)

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:charge) == charges
    assert Effects.count(:quote) == 1
  end

  test "every checkpoint that stood is taken back, leaving none" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    assert length(Store.standing(workflow.id)) == 3

    {:ok, []} = Magma.Unwind.run(reload(workflow))

    assert Store.standing(workflow.id) == []
    assert Effects.count({:undo, :quote}) == 1
    assert Effects.count({:undo, :charge}) == 1
    assert Effects.count({:undo, :ship}) == 1
  end

  test "steps are taken back newest first" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    Effects.reset()
    {:ok, []} = Magma.Unwind.run(reload(workflow))

    assert Effects.order() == [{:undo, :ship}, {:undo, :charge}, {:undo, :quote}]
  end

  test "a rollback stopped part way carries on from where the marks say" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    [newest | _rest] = Store.standing(workflow.id)
    {:ok, _marked} = Store.mark_undone(newest)

    Effects.reset()
    {:ok, []} = Magma.Unwind.run(reload(workflow))

    assert Effects.count({:undo, :ship}) == 0
    assert Effects.count({:undo, :charge}) == 1
    assert Effects.count({:undo, :quote}) == 1
  end

  test "an undo that fails leaves its checkpoint standing" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    Effects.fail_undo(:charge)

    assert {:error, errors} = Magma.Unwind.run(reload(workflow))
    assert [{:undo_failed, :charge, _reason}] = errors

    labels = workflow.id |> Store.standing() |> Enum.map(& &1.step_label)

    assert ":charge" in labels
    refute ":ship" in labels
  end

  test "cancelling a workflow takes back what it did and ends it cancelled" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    {:ok, _cancelling} = Magma.cancel(workflow.id)
    drain()

    assert reload(workflow).status == :cancelled
    assert Store.standing(workflow.id) == []
    assert Effects.count({:undo, :ship}) == 1
  end

  test "two rollbacks racing over one workflow take each step back once" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    loaded = reload(workflow)

    [one, two] =
      for _each <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Magma.TestRepo, self(), self())
          Magma.Unwind.run(loaded)
        end)
      end
      |> Task.await_many(5_000)

    assert {:ok, _} = one
    assert {:ok, _} = two

    assert Effects.count({:undo, :ship}) == 1
    assert Effects.count({:undo, :charge}) == 1
    assert Effects.count({:undo, :quote}) == 1
    assert Store.standing(workflow.id) == []
  end

  test "a checkpoint claimed by one rollback is left alone by another" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    [newest | _rest] = Store.standing(workflow.id)

    assert {:ok, claimed} = Store.claim_undo(newest)
    assert :taken = Store.claim_undo(claimed)
  end

  test "a checkpoint whose undo failed is left standing for another attempt" do
    {:ok, workflow} = Magma.start(Workflows.Undoable, %{order_id: "ord_1"})
    drain()

    Effects.fail_undo(:charge)
    {:error, _errors} = Magma.Unwind.run(reload(workflow))

    labels = workflow.id |> Store.standing() |> Enum.map(& &1.step_label)
    assert ":charge" in labels

    Effects.reset()
    assert {:ok, []} = Magma.Unwind.run(reload(workflow))
    assert Effects.count({:undo, :charge}) == 1
  end

  test "an undo sees the context the workflow's middleware prepared" do
    {:ok, workflow} = Magma.start(Workflows.Prepared, %{order_id: "ord_1"})
    drain()

    {:ok, []} = Magma.Unwind.run(reload(workflow))

    assert Effects.count({:undo, :quote, :yes}) == 1
    assert Effects.count({:undo, :charge, :yes}) == 1
  end

  test "a middleware that cannot prepare the context fails the rollback" do
    {:ok, workflow} = Magma.start(Workflows.Prepared, %{order_id: "ord_1"})
    drain()

    Effects.fail_init()

    assert {:error, [{:middleware_failed, _reason}]} = Magma.Unwind.run(reload(workflow))
    assert Effects.count({:undo, :quote, :yes}) == 0
    assert length(Store.standing(workflow.id)) == 2
  end

  test "cancelling a workflow the store has never seen reports it" do
    assert {:error, :no_such_workflow} = Magma.cancel("019faae3-0000-7000-8000-000000000000")
  end
end
