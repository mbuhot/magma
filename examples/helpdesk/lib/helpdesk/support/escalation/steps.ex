defmodule Helpdesk.Support.Escalation.Steps do
  @moduledoc "The two steps that are not an Ash action."

  defmodule Assess do
    @moduledoc """
    Decides how the escalation should read, from the actor and the tenant on the context.

    A plain step is handed the same context an Ash action reads, so reaching the actor here
    takes a pattern match and nothing else.
    """

    use Reactor.Step

    @impl true
    def run(%{ticket: ticket}, %{actor: actor, tenant: tenant}, _options) do
      {:ok,
       %{
         raised_by: actor.name,
         holds: actor.permissions,
         organisation: tenant,
         subject: ticket.subject
       }}
    end
  end

  defmodule Outcome do
    @moduledoc """
    Ends the run the way the decision says.

    A rejection is an error, which is what drives the rollback that puts the ticket back.
    """

    use Reactor.Step

    @impl true
    def run(%{ticket: ticket, decision: %{decision: :approved}}, _context, _options) do
      {:ok, ticket}
    end

    def run(%{ticket: ticket}, _context, _options) do
      {:error, %Helpdesk.Support.Rejected{ticket_id: ticket.id}}
    end
  end
end
