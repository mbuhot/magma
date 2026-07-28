defmodule Magma.WorkerTest do
  use Magma.DataCase, async: false
  use Oban.Testing, repo: Magma.TestRepo

  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    :ok
  end

  defp run_until_done(workflow) do
    Oban.drain_queue(queue: :default, with_recursion: true, with_safety: false)
    {:ok, reloaded} = Magma.fetch(workflow.id)
    reloaded
  end

  test "starting a workflow enqueues the job that will run it" do
    {:ok, workflow} = Magma.start(Workflows.Linear, %{order_id: "ord_1"})

    assert workflow.status == :pending
    assert_enqueued(worker: Magma.Worker, args: %{workflow_id: workflow.id})
  end

  test "a workflow that runs to the end is completed and carries its result" do
    {:ok, workflow} = Magma.start(Workflows.Linear, %{order_id: "ord_1"})

    done = run_until_done(workflow)

    assert done.status == :completed
    assert {:ship, _arguments} = done.result
  end

  test "a workflow records a step for each one it ran" do
    {:ok, workflow} = Magma.start(Workflows.Linear, %{order_id: "ord_1"})

    run_until_done(workflow)

    labels = workflow.id |> Magma.steps() |> Enum.map(& &1.step_label) |> Enum.sort()

    assert labels == [":charge", ":quote", ":ship"]
  end

  test "a workflow whose step keeps failing ends failed, carrying the error" do
    Effects.fail_after(:charge, 99)
    {:ok, workflow} = Magma.start(Workflows.Linear, %{order_id: "ord_1"})

    done = run_until_done(workflow)

    assert done.status == :failed
    assert done.error != nil
  end

  test "a step that failed once is the only one re-run when the job is retried" do
    Effects.fail_after(:charge, 1)
    {:ok, workflow} = Magma.start(Workflows.Linear, %{order_id: "ord_1"})

    Oban.drain_queue(queue: :default, with_recursion: true, with_safety: false)

    assert Effects.count(:quote) == 1
    assert Effects.count(:charge) == 1

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:quote) == 1
    assert Effects.count(:charge) == 2
    assert Effects.count(:ship) == 1
  end

  test "a job for a workflow the store has never seen is cancelled" do
    assert {:cancel, _reason} =
             Magma.Worker.perform(%Oban.Job{
               args: %{"workflow_id" => "019faae3-0000-7000-8000-000000000000"}
             })
  end

  test "the actor and tenant a workflow started with reach its steps" do
    {:ok, workflow} =
      Magma.start(Workflows.Linear, %{order_id: "ord_1"},
        actor: %{id: 7, roles: [:admin]},
        tenant: "acme"
      )

    {:ok, reloaded} = Magma.fetch(workflow.id)

    assert reloaded.actor == %{id: 7, roles: [:admin]}
    assert reloaded.tenant == "acme"
  end
end
