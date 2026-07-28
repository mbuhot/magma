defmodule Magma.Resource.Workflow.Transformer do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias Magma.Resource.Common
  alias Magma.Type.Term

  # Ash computes the primary key and the action defaults from the attributes it can see, so
  # the injected ones have to be in place first.
  @impl true
  def before?(_transformer), do: true

  @impl true
  def transform(dsl_state) do
    dsl_state
    |> Common.add_id()
    |> Builder.add_new_attribute(:module, :module, allow_nil?: false, public?: true)
    |> Builder.add_new_attribute(:inputs, Term, public?: true)
    |> Builder.add_new_attribute(:actor, Term, public?: true)
    |> Builder.add_new_attribute(:tenant, Term, public?: true)
    |> Builder.add_new_attribute(:status, Magma.Status,
      allow_nil?: false,
      public?: true,
      default: :pending
    )
    |> Builder.add_new_attribute(:parent_workflow_id, :uuid_v7, public?: true)
    |> Builder.add_new_attribute(:parent_signal, :string, public?: true)
    |> Builder.add_new_attribute(:result, Term, public?: true)
    |> Builder.add_new_attribute(:error, Term, public?: true)
    |> Builder.add_new_create_timestamp(:inserted_at, public?: true)
    |> Builder.add_new_update_timestamp(:updated_at, public?: true)
    |> Builder.add_new_action(:read, :read, primary?: true)
    |> Builder.add_new_action(:create, :start,
      primary?: true,
      accept: [:id, :module, :inputs, :actor, :tenant, :parent_workflow_id, :parent_signal]
    )
    |> Builder.add_new_action(:update, :set_status, accept: [:status], require_atomic?: false)
    |> Builder.add_new_action(:update, :complete,
      accept: [:result],
      require_atomic?: false,
      changes: [Common.set(:status, :completed)]
    )
    |> Builder.add_new_action(:update, :fail,
      accept: [:error],
      require_atomic?: false,
      changes: [Common.set(:status, :failed)]
    )
    |> Builder.add_new_action(:update, :cancelled,
      accept: [:error],
      require_atomic?: false,
      changes: [Common.set(:status, :cancelled)]
    )
  end
end
