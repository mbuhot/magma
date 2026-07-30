defmodule Helpdesk.Magma.Signal do
  @moduledoc false

  use Ash.Resource,
    domain: Helpdesk.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Signal]

  magma do
    workflow(Helpdesk.Magma.Workflow)
  end

  postgres do
    table("magma_signals")
    repo(Helpdesk.Repo)
  end
end
