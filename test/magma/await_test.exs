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
  end

  test "a wait with a deadline holds one job, scheduled for when it lapses" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})

    drain()

    assert [job] = all_enqueued(worker: Magma.Worker)
    assert job.state == "scheduled"
    assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
    assert job.args["workflow_id"] == workflow.id
  end

  test "a parked workflow records what it is waiting on" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    assert [waiter] = Store.waiters(workflow.id)
    assert waiter.name == "confirm"
    assert waiter.kind == :signal
  end

  test "a workflow that has ended is parked on nothing, even if an attempt re-parked it" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})
    drain()

    {:ok, _stray} = Store.park(workflow.id, "confirm", :signal, nil)
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert reload(workflow).status == :completed
    assert Store.waiters(workflow.id) == []
  end

  test "waits that depend on nothing all park together" do
    {:ok, workflow} = Magma.start(Workflows.Independent, %{order_id: "ord_1"})

    drain()

    names = workflow.id |> Store.waiters() |> Enum.map(& &1.name) |> Enum.sort()

    assert reload(workflow).status == :waiting
    assert names == ["left", "right"]
  end

  test "waits that park together are answered in whatever order they are answered" do
    {:ok, workflow} = Magma.start(Workflows.Independent, %{order_id: "ord_1"})
    drain()

    {:ok, _right} = Magma.signal(workflow.id, "right", :yes)
    drain()
    {:ok, _left} = Magma.signal(workflow.id, "left", :yes)
    drain()

    assert reload(workflow).status == :completed
    assert Effects.count(:join) == 1
  end

  test "a wait that has been answered is not parked on again" do
    {:ok, workflow} = Magma.start(Workflows.Independent, %{order_id: "ord_1"})
    drain()

    {:ok, _left} = Magma.signal(workflow.id, "left", :yes)
    drain()

    names = workflow.id |> Store.waiters() |> Enum.map(& &1.name)
    recorded = workflow.id |> Store.standing() |> Enum.map(& &1.step_label)

    assert reload(workflow).status == :waiting
    assert names == ["right"]
    assert recorded == [":left"]
  end

  test "what the engine writes reaches the application as it happens" do
    :ok = Magma.Test.Watcher.watch()

    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})
    drain()

    assert reload(workflow).status == :completed
    assert_received {:magma_wrote, Magma.Test.Store.Waiter, :park}
    assert_received {:magma_wrote, Magma.Test.Store.Waiter, :release}
    assert_received {:magma_wrote, Magma.Test.Store.Workflow, :set_status}
    assert_received {:magma_wrote, Magma.Test.Store.Workflow, :complete}
    assert_received {:magma_wrote, Magma.Test.Store.Checkpoint, :record}
  end

  defp available_jobs do
    Enum.filter(all_enqueued(worker: Magma.Worker), &(&1.state == "available"))
  end

  test "a workflow parked on one wait is still brought back by a signal for another" do
    {:ok, workflow} = Magma.start(Workflows.Staged, %{order_id: "ord_1"})
    drain()

    assert reload(workflow).status == :waiting
    assert available_jobs() == []

    {:ok, _second} = Magma.signal(workflow.id, "second", :yes)

    assert [job] = available_jobs()
    assert job.args["workflow_id"] == workflow.id
  end

  test "a workflow with an attempt already under way is still sent a job for what it is told" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    {:ok, _claimed} = Store.claim_workflow(workflow, 1, 60_000)

    Oban.drain_queue(queue: :default, with_recursion: false, with_safety: false)

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})

    assert [job] = available_jobs()
    assert job.args["workflow_id"] == workflow.id
  end

  test "a workflow with a job waiting its turn is not sent another for what it is told" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})

    assert [queued] = available_jobs()

    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{approver: "sam"})

    assert [^queued] = available_jobs()
  end

  test "waits reached one after another are answered whichever order they are told in" do
    {:ok, workflow} = Magma.start(Workflows.Staged, %{order_id: "ord_1"})
    drain()

    {:ok, _second} = Magma.signal(workflow.id, "second", :yes)
    drain()
    {:ok, _first} = Magma.signal(workflow.id, "first", :yes)
    drain()

    assert reload(workflow).status == :completed
    assert Effects.count(:join) == 1
  end

  defp lapse(workflow_id, signal) do
    past = DateTime.add(DateTime.utc_now(), -1, :second)
    {:ok, _aged} = Store.park(workflow_id, signal, :signal, past)
    :ok
  end

  defp resume(workflow_id) do
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow_id}})
  end

  defp attempt(workflow_id, job_id) do
    Magma.Worker.perform(%Oban.Job{id: job_id, args: %{"workflow_id" => workflow_id}})
  end

  test "jobs for one workflow reaching it at once run it once between them" do
    {:ok, workflow} = Magma.start(Workflows.Independent, %{order_id: "ord_1"})
    drain()

    {:ok, _left} = Magma.signal(workflow.id, "left", :yes)
    {:ok, _right} = Magma.signal(workflow.id, "right", :yes)

    outcomes =
      1..4
      |> Task.async_stream(fn attempt -> attempt(workflow.id, attempt) end, ordered: false)
      |> Enum.map(fn {:ok, outcome} -> outcome end)

    labels = workflow.id |> Store.standing() |> Enum.map(& &1.step_label)

    assert reload(workflow).status == :completed
    assert Enum.sort(labels) == [":join", ":left", ":right"]
    assert Effects.count(:join) == 1
    refute Enum.any?(outcomes, &match?({:error, _reason}, &1))
  end

  test "a job for a workflow another attempt holds waits its turn" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    {:ok, _held} = Store.claim_workflow(workflow, 1, 60_000)

    assert attempt(workflow.id, 2) == {:snooze, 1}
    assert reload(workflow).status == :pending
    assert Effects.count(:quote) == 0
  end

  test "a workflow held by an attempt that died is taken over once the lease lapses" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    {:ok, _held} = Store.claim_workflow(workflow, 1, 60_000)

    Application.put_env(:magma, :lease_ms, 1)
    on_exit(fn -> Application.delete_env(:magma, :lease_ms) end)

    assert attempt(workflow.id, 2) == :ok
    assert reload(workflow).status == :waiting
  end

  test "the attempt holding a workflow takes it again when its job is retried" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    {:ok, _held} = Store.claim_workflow(workflow, 7, 60_000)

    assert attempt(workflow.id, 7) == :ok
    assert reload(workflow).status == :waiting
  end

  test "a wait that goes unanswered past its window fails the workflow" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    :ok = lapse(workflow.id, "confirm")
    resume(workflow.id)

    failed = reload(workflow)

    assert failed.status == :failed
    assert Exception.message(failed.error) =~ ~s(waiting for "confirm" reached its deadline)
    assert Effects.count(:ship) == 0
    assert Store.waiters(workflow.id) == []
  end

  test "a wait told to give up hands the rest of the run a timeout to read" do
    {:ok, workflow} = Magma.start(Workflows.Lapsing, %{order_id: "ord_1"})
    drain()

    :ok = lapse(workflow.id, "confirm")
    resume(workflow.id)

    done = reload(workflow)

    confirmation =
      workflow.id |> Store.standing() |> Enum.find(&(&1.step_label == ":confirmation"))

    assert done.status == :completed
    assert confirmation.output == :timeout
    assert Effects.count(:ship) == 1
  end

  test "coming back to a wait still inside its window leaves it waiting on one visit" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})
    drain()

    [before] = all_enqueued(worker: Magma.Worker)

    resume(workflow.id)

    assert reload(workflow).status == :waiting
    assert [^before] = all_enqueued(worker: Magma.Worker)
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

  defp window_left(workflow_id, signal) do
    %{deadline: deadline} = Store.waiter(workflow_id, signal)
    DateTime.diff(deadline, DateTime.utc_now(), :millisecond)
  end

  test "a wait takes its window from the row that started it" do
    {:ok, workflow} = Magma.start(Workflows.Cooling, %{order_id: "ord_1", window_ms: 90_000})

    drain()

    assert reload(workflow).status == :waiting
    assert window_left(workflow.id, "confirm") in 80_000..90_000
  end

  test "a wait can have its window worked out by a named function and its policy" do
    {:ok, workflow} =
      Magma.start(Workflows.ScaledCooling, %{order_id: "ord_1", window_ms: 30_000})

    drain()

    assert reload(workflow).status == :waiting
    assert window_left(workflow.id, "confirm") in 80_000..90_000
  end

  test "a wait given a plain window in milliseconds still keeps it" do
    {:ok, workflow} = Magma.start(Workflows.Approval, %{order_id: "ord_1"})

    drain()

    assert window_left(workflow.id, "confirm") in 590_000..600_000
  end

  test "a window that answers differently later cannot move the one already running" do
    Application.put_env(:magma, :test_window_ms, 600_000)
    on_exit(fn -> Application.delete_env(:magma, :test_window_ms) end)

    {:ok, workflow} = Magma.start(Workflows.Shifting, %{order_id: "ord_1"})
    drain()

    %{deadline: parked} = Store.waiter(workflow.id, "confirm")

    Application.put_env(:magma, :test_window_ms, 1)
    resume(workflow.id)

    assert reload(workflow).status == :waiting
    assert %{deadline: ^parked} = Store.waiter(workflow.id, "confirm")
    assert Effects.count(:ship) == 0
  end

  test "a carried window that lapses unanswered fails the workflow" do
    {:ok, workflow} = Magma.start(Workflows.Cooling, %{order_id: "ord_1", window_ms: 20})
    drain()

    Process.sleep(40)
    resume(workflow.id)

    failed = reload(workflow)

    assert failed.status == :failed
    assert Exception.message(failed.error) =~ ~s(waiting for "confirm" reached its deadline)
    assert Effects.count(:ship) == 0
  end

  test "a carried window that lapses can hand the rest of the run a timeout to read" do
    {:ok, workflow} = Magma.start(Workflows.LenientCooling, %{order_id: "ord_1", window_ms: 20})
    drain()

    Process.sleep(40)
    resume(workflow.id)

    confirmation =
      workflow.id |> Store.standing() |> Enum.find(&(&1.step_label == ":confirmation"))

    assert reload(workflow).status == :completed
    assert confirmation.output == :timeout
    assert Effects.count(:ship) == 1
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
