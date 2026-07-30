defmodule Helpdesk.Support.Escalation do
  @moduledoc """
  A request that somebody look at a ticket.

  Asking needs no permission. Who asked is taken from the actor rather than passed in, so the
  record cannot disagree with the run that wrote it.
  """

  use Ash.Resource,
    domain: Helpdesk.Support,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("escalations")
    repo(Helpdesk.Repo)
  end

  pub_sub do
    module(HelpdeskWeb.Endpoint)
    prefix("escalations")
    publish_all(:create, [:org_id])
    publish_all(:destroy, [:org_id])
  end

  multitenancy do
    strategy(:attribute)
    attribute(:org_id)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:org_id, :uuid, allow_nil?: false, public?: true)
    attribute(:reason, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:ticket, Helpdesk.Support.Ticket, allow_nil?: false, public?: true)
    belongs_to(:raised_by, Helpdesk.Accounts.User, public?: true)
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  actions do
    defaults([:read])

    create :raise do
      accept([:ticket_id, :reason])
      change(relate_actor(:raised_by))
    end

    destroy :withdraw do
      description("Takes back a request that was never decided, when the run unwinds.")
      argument(:changeset, :term)
    end
  end
end
