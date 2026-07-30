defmodule Magma.NestingCompositeTest do
  @moduledoc """
  `group`, `around`, `recurse` and `compose` build a private reactor and run it inline, so
  their children never reach the outer plan and cannot be decorated. Each is one step with one
  checkpoint, and its children re-run together. These pin that.
  """

  use Magma.DataCase, async: false
  use Magma.Testing, repo: Magma.TestRepo

  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    :ok
  end

  test "a group records once, for the group and not its children" do
    {:ok, workflow} = Magma.start(Workflows.Grouped, %{order_id: "ord_1"})

    run_workflows()

    assert status(workflow) == :completed
    assert tape(workflow) == [":batch", ":after_group"]
  end

  test "a group's children re-run together when the run comes back before it recorded" do
    Effects.fail_after(:inner_two, 99)
    {:ok, workflow} = Magma.start(Workflows.Grouped, %{order_id: "ord_1"})

    run_workflows()

    assert Effects.count(:inner_one) == 1
    assert tape(workflow) == []
  end

  test "a step after a group replays without re-running the group" do
    {:ok, workflow} = Magma.start(Workflows.Grouped, %{order_id: "ord_1"})
    run_workflows()

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:inner_one) == 1
    assert Effects.count(:inner_two) == 1
    assert Effects.count(:after_group) == 1
  end

  test "a composed reactor records once, for the compose and not its inner steps" do
    {:ok, workflow} = Magma.start(Workflows.Composed, %{order_id: "ord_1"})

    run_workflows()

    assert status(workflow) == :completed
    assert Effects.count(:inner_step) == 1
    refute ":inner_step" in tape(workflow)
  end

  test "a composed reactor is not re-entered once it has recorded" do
    {:ok, workflow} = Magma.start(Workflows.Composed, %{order_id: "ord_1"})
    run_workflows()

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Effects.count(:inner_step) == 1
    assert Effects.count(:after_compose) == 1
  end

  test "a dispatch inside a recurse is refused, and dispatches nothing" do
    {:ok, workflow} = Magma.start(Workflows.Legs, %{transfer_id: "tr_1"})

    run_workflows()

    assert status(workflow) == :failed
    assert Effects.count(:leg_body) == 0
  end

  test "the refusal names the step and the composite it sits inside" do
    {:ok, workflow} = Magma.start(Workflows.Legs, %{transfer_id: "tr_1"})

    run_workflows()

    {:ok, failed} = Magma.Store.get_workflow(workflow.id)
    message = Exception.message(failed.error)

    assert message =~ "dispatch :leg sits inside :loop"
    assert message =~ "Move it into the outer reactor"
  end

  test "a compose's run step holds no checkpoint, since its value carries a live reactor" do
    {:ok, workflow} = Magma.start(Workflows.Composed, %{order_id: "ord_1"})

    run_workflows()

    assert tape(workflow) == [":sub", ":after_compose"]
    refute "{:compose, :sub}" in tape(workflow)
  end
end
