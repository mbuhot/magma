defmodule Helpdesk.Accounts do
  @moduledoc """
  Organisations, the people in them, and what those people may do.

  An organisation is a tenant. Every other resource here is scoped by one, so a read without a
  tenant is an error rather than a read across all of them.
  """

  use Ash.Domain

  resources do
    resource Helpdesk.Accounts.Organisation do
      define(:open_organisation, action: :create, args: [:name])
      define(:list_organisations, action: :read)
      define(:get_organisation, action: :read, get_by: [:id])
    end

    resource Helpdesk.Accounts.User do
      define(:hire, action: :create, args: [:name])
      define(:list_users, action: :with_permissions)
      define(:get_user, action: :read, get_by: [:id])
      define(:set_role, action: :set_role, get_by: [:id], args: [:role])
    end

    resource Helpdesk.Accounts.Grant do
      define(:grant, action: :create, args: [:user_id, :permission])
      define(:list_grants, action: :read)
      define(:revoke, action: :destroy)
    end
  end
end
