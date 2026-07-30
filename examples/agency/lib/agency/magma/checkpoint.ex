defmodule Agency.Magma.Checkpoint do
  @moduledoc false

  use Ash.Resource,
    domain: Agency.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Checkpoint],
    notifiers: [Ash.Notifier.PubSub]

  magma do
    workflow(Agency.Magma.Workflow)
  end

  postgres do
    table("magma_checkpoints")
    repo(Agency.Repo)
  end

  pub_sub do
    module(AgencyWeb.Endpoint)
    prefix("checkpoints")
    publish_all(:create, "all")
    publish_all(:update, "all")
  end
end
