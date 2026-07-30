defmodule Agency.Magma.Checkpoint do
  @moduledoc false

  use Ash.Resource,
    domain: Agency.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Checkpoint]

  magma do
    workflow(Agency.Magma.Workflow)
  end

  postgres do
    table("magma_checkpoints")
    repo(Agency.Repo)
  end
end
