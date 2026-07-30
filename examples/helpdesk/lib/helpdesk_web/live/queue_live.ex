defmodule HelpdeskWeb.QueueLive do
  @moduledoc """
  The tickets one person is holding, and the ones their team has open.

  Both lists are read with the viewer's organisation as the tenant and the viewer as the
  actor. Switching person changes the queue because the queue is theirs; switching
  organisation changes the people as well, because a user belongs to a tenant like everything
  else here.
  """

  use HelpdeskWeb, :live_view

  import HelpdeskWeb.Viewer

  alias Helpdesk.Accounts
  alias Helpdesk.Support
  alias Helpdesk.Support.Escalation.Workflow

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign_viewer(params)
     |> assign(page_title: "Tickets", scope: scope(params))
     |> load()}
  end

  @impl true
  def handle_event("organisation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{[org: id]}")}
  end

  def handle_event("actor", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{viewing(socket) |> Keyword.put(:as, id)}")}
  end

  def handle_event("cover", %{"id" => id}, socket) do
    Accounts.grant(id, :reassign_tickets, tenant: socket.assigns.organisation.id)

    {:noreply,
     socket
     |> put_flash(:info, "They can act on escalations now, including any already waiting.")
     |> load()}
  end

  def handle_event("uncover", %{"id" => id}, socket) do
    {:ok, grants} = Accounts.list_grants(tenant: socket.assigns.organisation.id)

    grants
    |> Enum.filter(&(&1.user_id == id))
    |> Enum.each(&Accounts.revoke(&1, tenant: socket.assigns.organisation.id))

    {:noreply,
     socket
     |> put_flash(:info, "Cover withdrawn. Anything still waiting is out of their hands again.")
     |> load()}
  end

  defp scope(%{"scope" => "team"}), do: :team
  defp scope(_params), do: :mine

  defp load(socket) do
    socket = refresh_viewer(socket)
    %{organisation: organisation, actor: actor, scope: scope} = socket.assigns

    tickets = read(scope, organisation, actor)
    {:ok, mine} = Support.my_tickets(actor.id, tenant: organisation.id, actor: actor)

    assign(socket, tickets: Enum.map(tickets, &with_escalation/1), mine: length(mine))
  end

  defp read(:mine, organisation, actor) do
    {:ok, tickets} = Support.my_tickets(actor.id, tenant: organisation.id, actor: actor)

    tickets
  end

  defp read(:team, organisation, actor) do
    {:ok, tickets} = Support.team_tickets(tenant: organisation.id, actor: actor)

    tickets
  end

  defp with_escalation(ticket), do: {ticket, Workflow.latest_for(ticket)}

  defp escalation_chip(nil), do: nil
  defp escalation_chip(%{status: :waiting}), do: {"waiting", "awaiting a team lead"}
  defp escalation_chip(%{status: :completed}), do: {"escalated", "escalated"}
  defp escalation_chip(%{status: status}) when status in [:failed, :cancelled], do: nil
  defp escalation_chip(_workflow), do: {"pending", "escalation running"}

  @impl true
  def render(assigns) do
    ~H"""
    <h1>{@organisation.name}</h1>
    <p class="sub">
      Signed in as {@actor.name}, {title(@actor.role) |> String.downcase()}.
      {if may_decide?(@actor),
        do: "You can act on escalations.",
        else: "You can ask for an escalation; a team lead decides it."}
    </p>

    <div class="tabs">
      <.link patch={~p"/?#{viewing(assigns)}"} class={@scope == :mine && "on"}>
        Assigned to me ({@mine})
      </.link>
      <.link
        patch={~p"/?#{viewing(assigns) |> Keyword.put(:scope, "team")}"}
        class={@scope == :team && "on"}
      >
        Open across the team
      </.link>
    </div>

    <div class="tickets">
      <.link
        :for={{ticket, run} <- @tickets}
        navigate={~p"/tickets/#{ticket.id}?#{viewing(assigns)}"}
        class="ticket"
      >
        <div class="avatar">{ticket.assignee && initials(ticket.assignee.name)}</div>

        <div>
          <div class="subject">{ticket.subject}</div>
          <div class="meta">Held by {(ticket.assignee && ticket.assignee.name) || "nobody"}</div>
        </div>

        <div class="right">
          <span :if={escalation_chip(run)} class={"chip #{elem(escalation_chip(run), 0)}"}>
            {elem(escalation_chip(run), 1)}
          </span>
          <span class={"chip #{ticket.status}"}>{ticket.status}</span>
        </div>
      </.link>

      <p :if={@tickets == []} class="empty">
        {if @scope == :mine, do: "Nothing assigned to you.", else: "Nothing open."}
      </p>
    </div>

    <div :if={may_decide?(@actor)} class="card" style="margin-top:1.5rem">
      <h2>Who can act on escalations</h2>
      <p class="sub" style="margin-bottom:1rem">
        Team leads always can. Give an agent cover and they can too — including on an
        escalation that is already waiting.
      </p>

      <div :for={person <- @people} class="row" style="padding:0.35rem 0">
        <div class="avatar">{initials(person.name)}</div>
        <div>
          <div>{person.name}</div>
          <div class="meta" style="color:var(--dim);font-size:0.85rem">{title(person.role)}</div>
        </div>

        <div style="margin-left:auto">
          <span :if={person.role == :team_lead} class="chip can">by role</span>

          <button
            :if={person.role == :agent && !may_decide?(person)}
            phx-click="cover"
            phx-value-id={person.id}
          >
            Give cover
          </button>

          <button
            :if={person.role == :agent && may_decide?(person)}
            class="danger"
            phx-click="uncover"
            phx-value-id={person.id}
          >
            Withdraw cover
          </button>
        </div>
      </div>
    </div>
    """
  end
end
