defmodule HelpdeskWeb.Viewer do
  @moduledoc """
  Who is looking, and which organisation they are looking at.

  A real deployment takes both from whatever signed the person in. This one carries them in
  the query string so they can be switched, and every page passes them to every read — the
  same two values `Magma.start/3` is given, doing the same job.
  """

  use Phoenix.Component

  alias Helpdesk.Accounts

  @doc "Reads the organisation and person out of the params, falling back to the first of each."
  @spec assign_viewer(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def assign_viewer(socket, params) do
    {:ok, organisations} = Accounts.list_organisations()

    organisation = pick(organisations, params["org"])
    {:ok, people} = Accounts.list_users(tenant: organisation.id)

    assign(socket,
      organisations: organisations,
      organisation: organisation,
      people: people,
      actor: pick(people, params["as"])
    )
  end

  @doc """
  Reads the viewer again, keeping who they are.

  Their authority is a calculation over rows that anybody can change, so a page that repaints
  has to ask again rather than trust what it was told when it mounted.
  """
  @spec refresh_viewer(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_viewer(%{assigns: %{organisation: organisation, actor: actor}} = socket) do
    assign_viewer(socket, %{"org" => organisation.id, "as" => actor.id})
  end

  @doc "The query string that keeps the current viewer across a navigation."
  @spec viewing(Phoenix.LiveView.Socket.t() | map()) :: keyword()
  def viewing(%{assigns: assigns}), do: viewing(assigns)

  def viewing(%{organisation: organisation, actor: actor}) do
    [org: organisation.id, as: actor.id]
  end

  @doc "Whether the person looking may act on an escalation."
  @spec may_decide?(map()) :: boolean()
  def may_decide?(%{permissions: permissions}), do: :reassign_tickets in permissions

  defp pick(candidates, nil), do: List.first(candidates)

  defp pick(candidates, id) do
    Enum.find(candidates, List.first(candidates), &(&1.id == id))
  end

  @doc """
  The organisation and person pickers.

  Switching either one reloads the page as somebody else, which is the whole demonstration:
  the queue below is whatever that pair is allowed to see.
  """
  attr(:organisations, :list, required: true)
  attr(:organisation, :map, required: true)
  attr(:people, :list, required: true)
  attr(:actor, :map, required: true)

  def switcher(assigns) do
    ~H"""
    <div class="switcher">
      <form id="organisation" phx-change="organisation">
        <select name="id" aria-label="Organisation">
          <option :for={org <- @organisations} value={org.id} selected={org.id == @organisation.id}>
            {org.name}
          </option>
        </select>
      </form>

      <form id="actor" phx-change="actor">
        <select name="id" aria-label="Signed in as">
          <option :for={person <- @people} value={person.id} selected={person.id == @actor.id}>
            {person.name} — {title(person.role)}
          </option>
        </select>
      </form>

      <span class={"chip #{if may_decide?(@actor), do: "can", else: "cannot"}"}>
        {if may_decide?(@actor), do: "can approve escalations", else: "cannot approve escalations"}
      </span>
    </div>
    """
  end

  @doc "A role as it should read on screen."
  @spec title(atom()) :: String.t()
  def title(:team_lead), do: "Team lead"
  def title(:agent), do: "Agent"

  @doc "Somebody's initials, for the avatar beside their name."
  @spec initials(String.t()) :: String.t()
  def initials(name) do
    name |> String.split(" ") |> Enum.map(&String.first/1) |> Enum.take(2) |> Enum.join()
  end
end
