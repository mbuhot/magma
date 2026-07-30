defmodule Helpdesk.Magma.Checkpoint do
  @moduledoc false

  use Ash.Resource,
    domain: Helpdesk.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Checkpoint]

  magma do
    workflow(Helpdesk.Magma.Workflow)
  end

  postgres do
    table("magma_checkpoints")
    repo(Helpdesk.Repo)
  end
end
