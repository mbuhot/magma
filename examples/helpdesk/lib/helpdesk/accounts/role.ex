defmodule Helpdesk.Accounts.Role do
  @moduledoc "What a user is, before anything is granted to them individually."

  use Ash.Type.Enum,
    values: [
      agent: "answers tickets, and may ask for one to be escalated",
      team_lead: "may act on an escalation, by virtue of the role"
    ]
end
