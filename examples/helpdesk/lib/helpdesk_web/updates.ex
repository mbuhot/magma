defmodule HelpdeskWeb.Updates do
  @moduledoc """
  What a page listens to while it is open.

  Every resource the console reads publishes on a topic named for its tenant, so a page
  subscribes to the organisation it is showing and repaints when anything in that organisation
  moves — a ticket, an escalation, a grant, or a run the engine woke in another process.
  """

  @kinds ~w(tickets escalations grants runs)

  @doc "Listens to one organisation, and stops listening to whichever came before."
  @spec follow(String.t() | nil, String.t()) :: :ok
  def follow(followed, followed), do: :ok

  def follow(previous, organisation_id) do
    for kind <- @kinds do
      if previous, do: Phoenix.PubSub.unsubscribe(Helpdesk.PubSub, topic(kind, previous))

      Phoenix.PubSub.subscribe(Helpdesk.PubSub, topic(kind, organisation_id))
    end

    :ok
  end

  defp topic(kind, organisation_id), do: "#{kind}:#{organisation_id}"
end
