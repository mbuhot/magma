defmodule Magma.Resource.Waiter.Transformer do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias Magma.Resource.Common

  @impl true
  def before?(_transformer), do: true

  @impl true
  def transform(dsl_state) do
    dsl_state
    |> Common.add_id()
    |> Common.add_workflow()
    |> Builder.add_new_attribute(:name, :string, allow_nil?: false, public?: true)
    |> Builder.add_new_attribute(:deadline, :utc_datetime_usec, public?: true)
    |> Builder.add_new_create_timestamp(:inserted_at, public?: true)
    |> Builder.add_new_identity(:unique_wait, [:workflow_id, :name])
    |> Builder.add_new_action(:read, :read, primary?: true)
    |> Builder.add_new_action(:create, :park,
      primary?: true,
      accept: [:workflow_id, :name, :deadline],
      upsert?: true,
      upsert_identity: :unique_wait
    )
    |> Builder.add_new_action(:destroy, :release, primary?: true)
  end
end
