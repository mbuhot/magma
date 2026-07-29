defmodule Payouts.Magma.Signal do
  @moduledoc false

  use Ash.Resource,
    domain: Payouts.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Signal]

  magma do
    workflow(Payouts.Magma.Workflow)
  end

  postgres do
    table("magma_signals")
    repo(Payouts.Repo)
  end
end
