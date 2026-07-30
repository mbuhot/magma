defmodule Helpdesk.Accounts.Permission do
  @moduledoc "A capability a user can hold, whether by role or by grant."

  use Ash.Type.Enum, values: [reassign_tickets: "may act on an escalation and move the ticket"]
end
