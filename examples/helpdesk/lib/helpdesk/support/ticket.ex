defmodule Helpdesk.Support.Ticket do
  @moduledoc """
  A customer's question, and whoever holds it.

  Reading one is scoped by the tenant and nothing else. Moving one to a different assignee
  needs `:reassign_tickets`, which is the single permission this example turns on.
  """

  use Ash.Resource,
    domain: Helpdesk.Support,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("tickets")
    repo(Helpdesk.Repo)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:org_id)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:org_id, :uuid, allow_nil?: false, public?: true)
    attribute(:subject, :string, allow_nil?: false, public?: true)

    attribute(:status, Helpdesk.Support.TicketStatus,
      allow_nil?: false,
      default: :open,
      public?: true
    )

    timestamps()
  end

  relationships do
    belongs_to(:assignee, Helpdesk.Accounts.User, public?: true)
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action(:open) do
      authorize_if(always())
    end

    policy action([:reassign, :restore_assignee]) do
      authorize_if(expr(:reassign_tickets in ^actor(:permissions)))
    end
  end

  actions do
    defaults([:read])

    read :by_id do
      get?(true)
      argument(:id, :uuid, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    create :open do
      accept([:subject, :assignee_id])
    end

    update :reassign do
      accept([:assignee_id])
      change(set_attribute(:status, :escalated))
    end

    update :restore_assignee do
      description("Puts a ticket back the way the changeset that moved it found it.")
      require_atomic?(false)
      argument(:changeset, :term, allow_nil?: false)

      change(fn changeset, _context ->
        %{data: was} = Ash.Changeset.get_argument(changeset, :changeset)

        changeset
        |> Ash.Changeset.force_change_attribute(:assignee_id, was.assignee_id)
        |> Ash.Changeset.force_change_attribute(:status, was.status)
      end)
    end
  end
end
