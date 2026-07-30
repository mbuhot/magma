defmodule Helpdesk.Magma.Waiter do
  @moduledoc false

  use Ash.Resource,
    domain: Helpdesk.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Waiter]

  magma do
    workflow(Helpdesk.Magma.Workflow)
  end

  postgres do
    table("magma_waiters")
    repo(Helpdesk.Repo)
  end
end
