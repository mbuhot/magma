defmodule Helpdesk.Support do
  @moduledoc """
  Tickets, the escalations raised against them, and the record of what was done.

  Every action here is authorized. The tenant scopes what can be seen; `:permissions` on the
  actor decides what can be moved.
  """

  use Ash.Domain

  resources do
    resource Helpdesk.Support.Ticket do
      define(:open_ticket, action: :open)
      define(:list_tickets, action: :read, default_options: [load: [:assignee]])
      define(:my_tickets, action: :assigned_to, args: [:assignee_id])
      define(:team_tickets, action: :open_in_team)
      define(:get_ticket, action: :by_id, args: [:id], default_options: [load: [:assignee]])
      define(:reassign_ticket, action: :reassign, get_by: [:id])
      define(:resolve_ticket, action: :resolve, get_by: [:id])
    end

    resource Helpdesk.Support.Escalation do
      define(:raise_escalation, action: :raise)
      define(:list_escalations, action: :read, default_options: [load: [:ticket, :raised_by]])
      define(:get_escalation, action: :read, get_by: [:id])
    end

    resource Helpdesk.Support.AuditEntry do
      define(:record_audit_entry, action: :record, args: [:action])
      define(:audit_trail, action: :read)
    end
  end
end
