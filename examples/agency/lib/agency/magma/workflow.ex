defmodule Agency.Magma.Workflow do
  @moduledoc false

  use Ash.Resource,
    domain: Agency.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Workflow]

  postgres do
    table("magma_workflows")
    repo(Agency.Repo)
  end
end
