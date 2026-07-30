defmodule Helpdesk.Support.AuditEntry do
  @moduledoc "What happened, and who it happened as."

  use Ash.Resource,
    domain: Helpdesk.Support,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("audit_entries")
    repo(Helpdesk.Repo)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:org_id)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:org_id, :uuid, allow_nil?: false, public?: true)
    attribute(:action, :string, allow_nil?: false, public?: true)
    attribute(:actor_name, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  actions do
    defaults([:read])

    create :record do
      accept([:action])

      change(fn changeset, %{actor: actor} ->
        Ash.Changeset.force_change_attribute(changeset, :actor_name, actor.name)
      end)
    end
  end
end
