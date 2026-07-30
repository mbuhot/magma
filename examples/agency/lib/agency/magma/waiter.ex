defmodule Agency.Magma.Waiter do
  @moduledoc false

  use Ash.Resource,
    domain: Agency.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Waiter],
    notifiers: [Ash.Notifier.PubSub]

  magma do
    workflow(Agency.Magma.Workflow)
  end

  postgres do
    table("magma_waiters")
    repo(Agency.Repo)
  end

  pub_sub do
    module(AgencyWeb.Endpoint)
    prefix("waits")
    publish_all(:create, "all")
    publish_all(:update, "all")
    publish_all(:destroy, "all")
  end
end
