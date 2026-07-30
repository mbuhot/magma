defmodule Magma.Test.Store.Waiter do
  @moduledoc "The waiter resource the suite runs against."

  use Ash.Resource,
    domain: Magma.Test.Store,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Magma.Test.Watcher],
    extensions: [Magma.Resource.Waiter]

  magma do
    workflow(Magma.Test.Store.Workflow)
  end

  postgres do
    table "magma_waiters"
    repo Magma.TestRepo
  end
end
