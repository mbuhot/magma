defmodule Magma.Test.Store.Signal do
  @moduledoc "The signal resource the suite runs against."

  use Ash.Resource,
    domain: Magma.Test.Store,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Signal]

  magma do
    workflow(Magma.Test.Store.Workflow)
  end

  postgres do
    table "magma_signals"
    repo Magma.TestRepo
  end
end
