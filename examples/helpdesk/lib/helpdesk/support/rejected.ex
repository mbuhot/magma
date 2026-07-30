defmodule Helpdesk.Support.Rejected do
  @moduledoc "Raised when an escalation is turned down, so the run unwinds and the ticket goes back."

  defexception [:ticket_id]

  @impl true
  def message(%{ticket_id: id}), do: "the escalation of ticket #{id} was rejected"
end
