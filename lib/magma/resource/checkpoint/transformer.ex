defmodule Magma.Resource.Checkpoint.Transformer do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias Magma.Resource.Common
  alias Magma.Type.Term

  @impl true
  def before?(_transformer), do: true

  @impl true
  def transform(dsl_state) do
    dsl_state
    |> Common.add_id()
    |> Common.add_workflow()
    |> Builder.add_new_attribute(:step_key, :binary, allow_nil?: false, public?: true)
    |> Builder.add_new_attribute(:step_label, :string, allow_nil?: false, public?: true)
    |> Builder.add_new_attribute(:output, Term, public?: true)
    |> Builder.add_new_attribute(:error, Term, public?: true)
    |> Builder.add_new_attribute(:undone_at, :utc_datetime_usec, public?: true)
    |> Builder.add_new_create_timestamp(:inserted_at, public?: true)
    |> Builder.add_new_identity(:unique_step, [:workflow_id, :step_key])
    |> Builder.add_new_action(:read, :read, primary?: true)
    |> Builder.add_new_action(:create, :record,
      primary?: true,
      accept: [:workflow_id, :step_key, :step_label, :output, :error]
    )
    |> Builder.add_new_action(:update, :mark_undone,
      accept: [],
      require_atomic?: false,
      changes: [Common.set(:undone_at, &DateTime.utc_now/0)]
    )
  end
end
