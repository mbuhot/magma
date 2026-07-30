defmodule Helpdesk.Magma.Workflow do
  @moduledoc false

  use Ash.Resource,
    domain: Helpdesk.Magma,
    data_layer: AshPostgres.DataLayer,
    extensions: [Magma.Resource.Workflow],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("magma_workflows")
    repo(Helpdesk.Repo)
  end

  pub_sub do
    module(HelpdeskWeb.Endpoint)
    prefix("runs")
    publish_all(:create, [:tenant])
    publish_all(:update, [:tenant])
    publish_all(:destroy, [:tenant])
  end
end
