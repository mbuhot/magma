defmodule Agency.Magma.Signal do
  @moduledoc false

  use Ash.Resource,
    domain: Agency.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Signal]

  magma do
    workflow(Agency.Magma.Workflow)
  end

  postgres do
    table("magma_signals")
    repo(Agency.Repo)
  end
end
