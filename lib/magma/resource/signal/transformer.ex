defmodule Magma.Resource.Signal.Transformer do
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
    |> Builder.add_new_attribute(:name, :string, allow_nil?: false, public?: true)
    |> Builder.add_new_attribute(:payload, Term, public?: true)
    |> Builder.add_new_attribute(:consumed_at, :utc_datetime_usec, public?: true)
    |> Builder.add_new_create_timestamp(:inserted_at, public?: true)
    |> Builder.add_new_action(:read, :read, primary?: true)
    |> Builder.add_new_action(:destroy, :destroy, primary?: true)
    |> Builder.add_new_action(:create, :deliver,
      primary?: true,
      accept: [:workflow_id, :name, :payload]
    )
    |> Builder.add_new_action(:update, :consume,
      accept: [],
      require_atomic?: false,
      changes: [Common.set(:consumed_at, &DateTime.utc_now/0)]
    )
  end
end
