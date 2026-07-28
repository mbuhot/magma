defmodule Magma.Test.Store.Checkpoint do
  @moduledoc "The checkpoint resource the suite runs against."

  use Ash.Resource,
    domain: Magma.Test.Store,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Checkpoint]

  magma do
    workflow(Magma.Test.Store.Workflow)
  end

  postgres do
    table "magma_checkpoints"
    repo Magma.TestRepo
  end
end
