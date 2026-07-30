defmodule Agency.Magma.Waiter do
  @moduledoc false

  use Ash.Resource,
    domain: Agency.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Waiter]

  magma do
    workflow(Agency.Magma.Workflow)
  end

  postgres do
    table("magma_waiters")
    repo(Agency.Repo)
  end
end
