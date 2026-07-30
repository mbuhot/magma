defmodule Helpdesk.Accounts.Role do
  @moduledoc "What a user is, before anything is granted to them individually."

  use Ash.Type.Enum,
    values: [
      agent: "answers tickets, and may ask for one to be escalated",
      manager: "may reassign a ticket, by virtue of the role"
    ]
end
