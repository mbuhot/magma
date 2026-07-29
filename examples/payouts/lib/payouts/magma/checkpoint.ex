defmodule Payouts.Magma.Checkpoint do
  @moduledoc false

  use Ash.Resource,
    domain: Payouts.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Checkpoint]

  magma do
    workflow(Payouts.Magma.Workflow)
  end

  postgres do
    table("magma_checkpoints")
    repo(Payouts.Repo)
  end
end
