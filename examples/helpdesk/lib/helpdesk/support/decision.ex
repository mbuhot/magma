defmodule Helpdesk.Support.Decision do
  @moduledoc "What came back when somebody looked at an escalation."

  use Ash.Type.Enum,
    values: [
      approved: "reassign the ticket",
      rejected: "leave it where it was"
    ]
end
