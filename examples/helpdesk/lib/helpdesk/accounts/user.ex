defmodule Helpdesk.Accounts.User do
  @moduledoc """
  Someone who works a queue of tickets, and the actor a workflow runs as.

  What a workflow persists of a user is their id. What authorizes its steps is `:permissions`,
  calculated from the role and the grants that stand at the moment it is read.
  """

  use Ash.Resource, domain: Helpdesk.Accounts, data_layer: AshPostgres.DataLayer

  postgres do
    table("users")
    repo(Helpdesk.Repo)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:org_id)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:org_id, :uuid, allow_nil?: false, public?: true)
    attribute(:name, :string, allow_nil?: false, public?: true)

    attribute(:role, Helpdesk.Accounts.Role,
      allow_nil?: false,
      default: :agent,
      public?: true
    )

    timestamps()
  end

  relationships do
    belongs_to(:organisation, Helpdesk.Accounts.Organisation, source_attribute: :org_id)
    has_many(:grants, Helpdesk.Accounts.Grant)
  end

  calculations do
    calculate(:permissions, {:array, Helpdesk.Accounts.Permission}, Helpdesk.Accounts.Calculations.Permissions,
      public?: true
    )
  end

  actions do
    defaults([:read, create: [:name, :role]])

    read :with_permissions do
      description("A user with the authority they hold right now.")
      prepare(build(load: [:permissions]))
    end

    update :set_role do
      accept([:role])
    end
  end
end
