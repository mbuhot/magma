defmodule Helpdesk.Accounts.Permission do
  @moduledoc "A capability a user can hold, whether by role or by grant."

  use Ash.Type.Enum, values: [reassign_tickets: "may move a ticket to another assignee"]
end
