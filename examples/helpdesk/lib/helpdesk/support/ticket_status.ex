defmodule Helpdesk.Support.TicketStatus do
  @moduledoc "Where a ticket stands."

  use Ash.Type.Enum,
    values: [
      open: "waiting on whoever holds it",
      escalated: "moved to someone else after an escalation was approved",
      closed: "answered"
    ]
end
