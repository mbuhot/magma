defmodule Helpdesk.Magma.Workflow do
  @moduledoc false

  use Ash.Resource,
    domain: Helpdesk.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Workflow]

  postgres do
    table("magma_workflows")
    repo(Helpdesk.Repo)
  end
end
