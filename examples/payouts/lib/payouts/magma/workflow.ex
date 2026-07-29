defmodule Payouts.Magma.Workflow do
  @moduledoc false

  use Ash.Resource,
    domain: Payouts.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Workflow]

  postgres do
    table("magma_workflows")
    repo(Payouts.Repo)
  end
end
