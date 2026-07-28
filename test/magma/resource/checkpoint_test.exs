defmodule Magma.Resource.CheckpointTest do
  use Magma.DataCase, async: true

  alias Magma.Test.Store.Checkpoint
  alias Magma.Test.Store.Workflow

  setup do
    {:ok, workflow} =
      Workflow
      |> Ash.Changeset.for_create(:start, %{module: Workflow, inputs: %{}})
      |> Ash.create()

    %{workflow: workflow}
  end

  defp record(workflow, attrs) do
    defaults = %{workflow_id: workflow.id, step_key: <<1, 2, 3>>, step_label: ":charge_card"}

    Checkpoint
    |> Ash.Changeset.for_create(:record, Map.merge(defaults, attrs))
    |> Ash.create()
  end

  test "the output a step produced comes back as it went in", %{workflow: workflow} do
    {:ok, checkpoint} = record(workflow, %{output: {:ok, %{charge_id: "ch_1", amount: 4999}}})
    {:ok, reloaded} = Ash.get(Checkpoint, checkpoint.id)

    assert reloaded.output == {:ok, %{charge_id: "ch_1", amount: 4999}}
  end

  test "a fresh checkpoint stands, having not been undone", %{workflow: workflow} do
    {:ok, checkpoint} = record(workflow, %{output: :done})

    assert checkpoint.undone_at == nil
  end

  test "one step cannot be recorded twice for the same workflow", %{workflow: workflow} do
    {:ok, _first} = record(workflow, %{step_key: <<9, 9>>, output: :first})

    assert {:error, %Ash.Error.Invalid{}} =
             record(workflow, %{step_key: <<9, 9>>, output: :second})
  end

  test "the same step can be recorded for two different workflows", %{workflow: workflow} do
    {:ok, other} =
      Workflow
      |> Ash.Changeset.for_create(:start, %{module: Workflow, inputs: %{}})
      |> Ash.create()

    {:ok, _one} = record(workflow, %{step_key: <<7>>, output: :a})
    {:ok, _two} = record(other, %{step_key: <<7>>, output: :b})
  end

  test "marking a checkpoint undone records when it was taken back", %{workflow: workflow} do
    {:ok, checkpoint} = record(workflow, %{output: :charged})

    {:ok, undone} =
      checkpoint
      |> Ash.Changeset.for_update(:mark_undone, %{})
      |> Ash.update()

    assert %DateTime{} = undone.undone_at
  end

  test "checkpoints order by id in the order they were recorded", %{workflow: workflow} do
    {:ok, first} = record(workflow, %{step_key: <<1>>, step_label: ":quote", output: :q})
    {:ok, second} = record(workflow, %{step_key: <<2>>, step_label: ":charge", output: :c})
    {:ok, third} = record(workflow, %{step_key: <<3>>, step_label: ":ship", output: :s})

    ordered =
      Checkpoint
      |> Ash.Query.sort(id: :asc)
      |> Ash.read!()
      |> Enum.map(& &1.id)

    assert ordered == [first.id, second.id, third.id]
  end
end
