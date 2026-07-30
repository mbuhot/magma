defmodule Helpdesk.Accounts.Grant do
  @moduledoc """
  A capability given to one user.

  Grants are rows, so authority can be handed over and taken away while a workflow is parked.
  That is the whole point of them here.
  """

  use Ash.Resource, domain: Helpdesk.Accounts, data_layer: AshPostgres.DataLayer

  postgres do
    table("grants")
    repo(Helpdesk.Repo)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:org_id)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:org_id, :uuid, allow_nil?: false, public?: true)
    attribute(:permission, Helpdesk.Accounts.Permission, allow_nil?: false, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:user, Helpdesk.Accounts.User, allow_nil?: false, public?: true)
  end

  identities do
    identity(:one_per_user, [:user_id, :permission])
  end

  actions do
    defaults([:read, :destroy, create: [:user_id, :permission]])
  end
end
