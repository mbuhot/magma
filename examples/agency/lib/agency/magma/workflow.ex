defmodule Agency.Magma.Workflow do
  @moduledoc false

  use Ash.Resource,
    domain: Agency.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Workflow],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("magma_workflows")
    repo(Agency.Repo)
  end

  pub_sub do
    module(AgencyWeb.Endpoint)
    prefix("runs")
    publish_all(:create, "all")
    publish_all(:update, "all")
  end
end
