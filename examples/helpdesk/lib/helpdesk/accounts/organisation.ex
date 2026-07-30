defmodule Helpdesk.Accounts.Organisation do
  @moduledoc """
  A tenant.

  The one resource that is not itself multitenant, because it is the thing every other
  resource is scoped by.
  """

  use Ash.Resource, domain: Helpdesk.Accounts, data_layer: AshPostgres.DataLayer

  postgres do
    table("organisations")
    repo(Helpdesk.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  actions do
    defaults([:read, create: [:name]])
  end
end
