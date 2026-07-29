defmodule Magma.RunTest do
  use Magma.DataCase, async: false

  alias Magma.Run
  alias Magma.Store
  alias Magma.Test.Effects
  alias Magma.Test.Workflows

  setup do
    Effects.reset()
    :ok
  end

  defp start(module, inputs \\ %{order_id: "ord_1"}) do
    {:ok, workflow} = Store.start_workflow(%{module: module, inputs: inputs})
    workflow
  end

  defp labels(workflow) do
    workflow.id |> Store.standing() |> Enum.map(& &1.step_label) |> Enum.sort()
  end

  test "a run that finishes records every step it ran" do
    workflow = start(Workflows.Linear)

    assert {:ok, {:ship, _arguments}} = Run.run(workflow)
    assert labels(workflow) == [":charge", ":quote", ":ship"]
  end

  test "a second run of a finished workflow re-executes nothing" do
    workflow = start(Workflows.Linear)

    {:ok, first} = Run.run(workflow)
    {:ok, second} = Run.run(workflow)

    assert first == second
    assert Effects.count(:quote) == 1
    assert Effects.count(:charge) == 1
    assert Effects.count(:ship) == 1
  end

  test "a run resuming after a failure repeats no step that finished" do
    Effects.fail_after(:charge, 1)
    workflow = start(Workflows.Linear)

    assert {:error, _reason} = Run.run(workflow)
    assert Effects.count(:quote) == 1
    assert Effects.count(:charge) == 1
    assert Effects.count(:ship) == 0

    assert {:ok, {:ship, _arguments}} = Run.run(workflow)

    assert Effects.count(:quote) == 1
    assert Effects.count(:charge) == 2
    assert Effects.count(:ship) == 1
  end

  test "a replayed step feeds the same value downstream that it did the first time" do
    workflow = start(Workflows.Linear, %{order_id: "ord_7"})

    {:ok, first} = Run.run(workflow)
    {:ok, second} = Run.run(workflow)

    assert {:ship, %{charge: {:charge, %{quote: {:quote, %{order_id: "ord_7"}}}}}} = first
    assert second == first
  end

  test "parallel branches each record on their own" do
    workflow = start(Workflows.Parallel)

    assert {:ok, {:join, _arguments}} = Run.run(workflow)
    assert labels(workflow) == [":join", ":left", ":right"]
  end

  test "a branch that finished before a failure is not re-run" do
    Effects.fail_after(:join, 1)
    workflow = start(Workflows.Parallel)

    assert {:error, _reason} = Run.run(workflow)
    assert {:ok, _result} = Run.run(workflow)

    assert Effects.count(:left) == 1
    assert Effects.count(:right) == 1
    assert Effects.count(:join) == 2
  end

  test "the workflow's inputs reach the steps that read them" do
    workflow = start(Workflows.Linear, %{order_id: "ord_42"})

    {:ok, {:ship, _arguments}} = Run.run(workflow)

    quote_step = Enum.find(Store.standing(workflow.id), &(&1.step_label == ":quote"))

    assert quote_step.output == {:quote, %{order_id: "ord_42"}}
  end

  test "a step with a recorded output is not re-judged by its own guard" do
    Effects.reset()
    Application.put_env(:magma, :test_gate, true)
    on_exit(fn -> Application.delete_env(:magma, :test_gate) end)

    workflow = start(Workflows.Gated)
    {:ok, _first} = Run.run(workflow)

    assert Effects.count(:gated) == 1

    Application.put_env(:magma, :test_gate, false)
    {:ok, _second} = Run.run(workflow)

    assert Effects.count(:gated) == 1
    assert ":gated" in labels(workflow)
  end

  test "a step its guard skipped records nothing" do
    Application.put_env(:magma, :test_gate, false)
    on_exit(fn -> Application.delete_env(:magma, :test_gate) end)

    workflow = start(Workflows.Gated)
    {:ok, _result} = Run.run(workflow)

    assert Effects.count(:gated) == 0
    refute ":gated" in labels(workflow)
  end

  test "two workflows of the same module keep their checkpoints apart" do
    one = start(Workflows.Linear, %{order_id: "ord_a"})
    two = start(Workflows.Linear, %{order_id: "ord_b"})

    {:ok, _first} = Run.run(one)
    {:ok, _second} = Run.run(two)

    assert length(Store.standing(one.id)) == 3
    assert length(Store.standing(two.id)) == 3

    quote_for = fn workflow ->
      Store.standing(workflow.id)
      |> Enum.find(&(&1.step_label == ":quote"))
      |> Map.fetch!(:output)
    end

    assert quote_for.(one) == {:quote, %{order_id: "ord_a"}}
    assert quote_for.(two) == {:quote, %{order_id: "ord_b"}}
  end
end
