defmodule Payouts.Magma.Waiter do
  @moduledoc false

  use Ash.Resource,
    domain: Payouts.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Waiter]

  magma do
    workflow(Payouts.Magma.Workflow)
  end

  postgres do
    table("magma_waiters")
    repo(Payouts.Repo)
  end
end
