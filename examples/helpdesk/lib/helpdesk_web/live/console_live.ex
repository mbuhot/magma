defmodule HelpdeskWeb.ConsoleLive do
  @moduledoc """
  The queue, seen as somebody.

  The two switchers at the top are the whole point: they set the actor and the tenant every
  query on this page passes, so the console is subject to exactly what a workflow is. Change
  the organisation and the tickets change with it, because tenancy scopes the read.

  Granting `:reassign_tickets` here while a run is parked is the demonstration. The run's row
  does not change — it holds an id — and the next attempt authorizes against the grant.
  """

  use HelpdeskWeb, :live_view

  alias Helpdesk.Accounts
  alias Helpdesk.Support
  alias Helpdesk.Support.Escalation.Workflow

  @refresh 750

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, self(), :refresh)

    {:ok, organisations} = Accounts.list_organisations()

    {:ok,
     socket
     |> assign(page_title: "queue", organisations: organisations)
     |> assign(organisation: List.first(organisations))
     |> pick_actor()
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("organisation", %{"id" => id}, socket) do
    organisation = Enum.find(socket.assigns.organisations, &(&1.id == id))

    {:noreply, socket |> assign(organisation: organisation) |> pick_actor() |> load()}
  end

  def handle_event("actor", %{"id" => id}, socket) do
    {:noreply, assign(socket, :actor, Enum.find(socket.assigns.people, &(&1.id == id)))}
  end

  def handle_event("grant", %{"id" => id}, socket) do
    Accounts.grant(id, :reassign_tickets, tenant: tenant(socket))

    {:noreply, socket |> put_flash(:info, "Granted. A parked run picks it up.") |> load()}
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    {:ok, grants} = Accounts.list_grants(tenant: tenant(socket))

    grants
    |> Enum.filter(&(&1.user_id == id))
    |> Enum.each(&Accounts.revoke(&1, tenant: tenant(socket)))

    {:noreply, socket |> put_flash(:info, "Revoked. A parked run loses it too.") |> load()}
  end

  def handle_event("escalate", %{"ticket_id" => ticket_id, "reason" => reason}, socket) do
    ticket = Enum.find(socket.assigns.tickets, &(&1.id == ticket_id))

    case Workflow.start(ticket, reason, socket.assigns.actor) do
      {:ok, workflow} -> {:noreply, push_navigate(socket, to: ~p"/escalations/#{workflow.id}")}
      {:error, error} -> {:noreply, put_flash(socket, :error, message(error))}
    end
  end

  defp pick_actor(socket) do
    {:ok, people} = Accounts.list_users(tenant: tenant(socket))

    assign(socket, people: people, actor: List.first(people))
  end

  defp load(socket) do
    tenant = tenant(socket)
    actor = socket.assigns.actor

    {:ok, people} = Accounts.list_users(tenant: tenant)
    {:ok, tickets} = Support.list_tickets(tenant: tenant, actor: actor)

    socket
    |> assign(people: people, tickets: tickets, runs: runs(tenant))
    |> assign(actor: Enum.find(people, &(&1.id == actor.id)) || actor)
    |> assign(elsewhere: elsewhere(socket))
  end

  # Magma's rows are one table for every organisation, so a tenant's runs are the ones whose
  # recorded tenant is this one.
  defp runs(tenant) do
    Helpdesk.Magma.Workflow
    |> Ash.read!()
    |> Enum.filter(&(&1.tenant == tenant))
    |> Enum.sort_by(& &1.id, :desc)
  end

  # What a different organisation sees at this same moment, read as one of their people.
  defp elsewhere(socket) do
    case Enum.reject(socket.assigns.organisations, &(&1.id == tenant(socket))) do
      [] ->
        nil

      [other | _rest] ->
        {:ok, people} = Accounts.list_users(tenant: other.id)
        {:ok, tickets} = Support.list_tickets(tenant: other.id, actor: List.first(people))

        %{organisation: other, tickets: tickets}
    end
  end

  defp tenant(socket), do: socket.assigns.organisation.id

  defp message(error) when is_exception(error), do: Exception.message(error)
  defp message(error), do: inspect(error)

  defp holds?(person, permission), do: permission in person.permissions

  defp short(id), do: String.slice(id, 0, 8)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="panel" style="margin-bottom:1rem">
      <div class="row">
        <form id="organisation" phx-change="organisation" style="flex:1">
          <label>Organisation — the tenant every query below is scoped by</label>
          <select name="id">
            <option :for={org <- @organisations} value={org.id} selected={org.id == @organisation.id}>
              {org.name}
            </option>
          </select>
        </form>

        <form id="actor" phx-change="actor" style="flex:1">
          <label>Signed in as — the actor every query below authorizes as</label>
          <select name="id">
            <option :for={person <- @people} value={person.id} selected={person.id == @actor.id}>
              {person.name} ({person.role})
            </option>
          </select>
        </form>
      </div>

      <p class="hint" style="margin:0.6rem 0 0">
        Holding: <span class="mono">{Layouts.permissions(@actor.permissions)}</span>
      </p>
    </div>

    <div class="grid">
      <div class="panel">
        <h2>Tickets in {@organisation.name}</h2>

        <table>
          <tr>
            <th>Subject</th>
            <th>Held by</th>
            <th>Status</th>
          </tr>
          <tr :for={ticket <- @tickets}>
            <td>{ticket.subject}</td>
            <td>{ticket.assignee && ticket.assignee.name}</td>
            <td><span class={"chip #{ticket.status}"}>{ticket.status}</span></td>
          </tr>
        </table>

        <p :if={@tickets == []} class="empty">Nothing in this queue.</p>
      </div>

      <div class="panel">
        <h2>Ask for an escalation</h2>
        <p class="hint">
          Raising needs no permission. Acting on the decision needs
          <span class="mono">reassign_tickets</span>, and that is read when the run wakes.
        </p>

        <form id="escalate" phx-submit="escalate">
          <label>Ticket</label>
          <select name="ticket_id">
            <option :for={ticket <- @tickets} value={ticket.id}>{ticket.subject}</option>
          </select>

          <label style="margin-top:0.7rem">Reason</label>
          <input type="text" name="reason" value="customer waiting three days" />

          <div class="row" style="margin-top:0.7rem">
            <button class="primary" type="submit" disabled={@tickets == []}>Raise it</button>
          </div>
        </form>
      </div>

      <div class="panel">
        <h2>Who may reassign</h2>
        <p class="hint">
          A grant is a row. Give one to somebody with a run parked, then approve it.
        </p>

        <table>
          <tr :for={person <- @people}>
            <td>{person.name}</td>
            <td class="value">{Layouts.permissions(person.permissions)}</td>
            <td style="text-align:right">
              <button
                :if={!holds?(person, :reassign_tickets)}
                phx-click="grant"
                phx-value-id={person.id}
              >
                grant
              </button>
              <button
                :if={holds?(person, :reassign_tickets) && person.role == :agent}
                class="danger"
                phx-click="revoke"
                phx-value-id={person.id}
              >
                revoke
              </button>
              <span :if={person.role == :manager} class="chip">by role</span>
            </td>
          </tr>
        </table>
      </div>

      <div class="panel">
        <h2>Runs in {@organisation.name}</h2>

        <table>
          <tr :for={run <- @runs}>
            <td>
              <.link navigate={~p"/escalations/#{run.id}"}>
                <span class="mono">{short(run.id)}</span>
              </.link>
            </td>
            <td><span class={"chip #{run.status}"}>{run.status}</span></td>
          </tr>
        </table>

        <p :if={@runs == []} class="empty">No escalation has been raised here yet.</p>
      </div>

      <div :if={@elsewhere} class="panel">
        <h2>What {@elsewhere.organisation.name} sees right now</h2>
        <p class="hint">The same page, the same code, a different tenant.</p>

        <table>
          <tr :for={ticket <- @elsewhere.tickets}>
            <td>{ticket.subject}</td>
            <td><span class={"chip #{ticket.status}"}>{ticket.status}</span></td>
          </tr>
        </table>

        <p :if={@elsewhere.tickets == []} class="empty">Nothing in their queue.</p>
      </div>
    </div>
    """
  end
end
