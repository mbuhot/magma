defmodule HelpdeskWeb.TicketLive do
  @moduledoc """
  One ticket, and whatever is happening to it.

  Anybody may ask for an escalation. Only somebody who can act on one sees the decision
  controls, and whether they can is read at the moment the page renders — the same read the
  workflow makes when it wakes.

  The escalation itself is a durable run: asking parks it, deciding wakes it. The history at
  the bottom is what the engine recorded.
  """

  use HelpdeskWeb, :live_view

  import HelpdeskWeb.Viewer

  alias Helpdesk.Support
  alias Helpdesk.Support.Escalation.Workflow

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => ticket_id} = params, _uri, socket) do
    {:noreply,
     socket
     |> assign_viewer(params)
     |> assign(ticket_id: ticket_id, page_title: "Ticket")
     |> load()}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("organisation", %{"organisation_id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/?#{[org: id]}")}
  end

  def handle_event("actor", %{"actor_id" => id}, socket) do
    viewing = Keyword.put(viewing(socket), :as, id)

    {:noreply, push_patch(socket, to: ~p"/tickets/#{socket.assigns.ticket_id}?#{viewing}")}
  end

  def handle_event("escalate", %{"reason" => reason}, socket) do
    socket.assigns.ticket
    |> Workflow.start(reason, socket.assigns.actor)
    |> answered(socket, "Escalation requested. A team lead has to decide it.")
  end

  def handle_event("approve", %{"assignee_id" => assignee_id}, socket) do
    socket.assigns.run.id
    |> Workflow.decide(:approved, socket.assigns.actor.id, assignee_id)
    |> answered(socket, "Approved. The ticket is moving.")
  end

  def handle_event("decline", _params, socket) do
    socket.assigns.run.id
    |> Workflow.decide(:rejected, socket.assigns.actor.id, nil)
    |> answered(socket, "Declined. The ticket stays where it was.")
  end

  def handle_event("resolve", _params, socket) do
    %{ticket: ticket, organisation: organisation, actor: actor} = socket.assigns

    :ok = Workflow.abandon(ticket)

    ticket.id
    |> Support.resolve_ticket(tenant: organisation.id, actor: actor)
    |> answered(socket, "Resolved. Nothing further happens to this ticket.")
  end

  defp answered({:ok, _result}, socket, message),
    do: {:noreply, socket |> put_flash(:info, message) |> load()}

  defp answered({:error, error}, socket, _message),
    do: {:noreply, socket |> put_flash(:error, message(error)) |> load()}

  defp load(socket) do
    socket = refresh_viewer(socket)
    %{organisation: organisation, actor: actor} = socket.assigns

    {:ok, ticket} =
      Support.get_ticket(socket.assigns.ticket_id, tenant: organisation.id, actor: actor)

    run = Workflow.latest_for(ticket)

    socket
    |> assign(ticket: ticket, run: run)
    |> assign(history: history(ticket, run, organisation, actor))
  end

  defp history(ticket, run, organisation, actor) do
    {:ok, entries} = Support.audit_trail(tenant: organisation.id, actor: actor)

    opened = [%{text: "Ticket opened", at: ticket.inserted_at}]

    decided =
      entries
      |> Enum.filter(&(&1.inserted_at >= ticket.inserted_at))
      |> Enum.map(&%{text: "#{&1.actor_name} decided an escalation", at: &1.inserted_at})

    Enum.sort_by(opened ++ decided ++ run_events(run), & &1.at, DateTime)
  end

  defp run_events(nil), do: []

  defp run_events(run) do
    [%{text: state(run.status), at: run.inserted_at}]
  end

  defp state(:waiting), do: "Escalation requested — waiting for a team lead"
  defp state(:completed), do: "Escalation approved, and the ticket was reassigned"
  defp state(:failed), do: "Escalation did not go through — the ticket is unchanged"
  defp state(:unwinding), do: "Escalation is being taken back"
  defp state(:cancelled), do: "Escalation taken back when the ticket was resolved"
  defp state(_status), do: "Escalation running"

  defp waiting?(%{status: :waiting}), do: true
  defp waiting?(_run), do: false

  defp closed?(%{status: :closed}), do: true
  defp closed?(_ticket), do: false

  defp open?(nil), do: false
  defp open?(%{status: status}), do: status in [:pending, :running, :waiting, :unwinding]

  defp tape(nil), do: []
  defp tape(run), do: run.id |> Magma.steps() |> Enum.sort_by(& &1.id)

  defp message(error) when is_exception(error), do: Exception.message(error)
  defp message(error), do: inspect(error, pretty: true)

  defp value(term), do: inspect(term, pretty: true, limit: 6)

  defp on(at), do: Calendar.strftime(at, "%d %b %H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <.link navigate={~p"/?#{viewing(assigns)}"} class="back">← All tickets</.link>

    <h1>{@ticket.subject}</h1>
    <p class="sub">
      <span class={"chip #{@ticket.status}"}>{@ticket.status}</span>
      <span style="margin-left:0.5rem">
        Held by {(@ticket.assignee && @ticket.assignee.name) || "nobody"}
      </span>
      <button :if={!closed?(@ticket)} phx-click="resolve" style="margin-left:0.75rem">
        {if waiting?(@run), do: "Resolve and drop the escalation", else: "Resolve"}
      </button>
    </p>

    <div :if={!open?(@run) && !closed?(@ticket)} class="card">
      <h2>Ask for an escalation</h2>
      <form id="escalate" phx-submit="escalate">
        <label for="reason">Why does this need a team lead?</label>
        <textarea id="reason" name="reason">The customer has been waiting three days.</textarea>

        <div class="row" style="margin-top:0.75rem">
          <button class="primary" type="submit">Request escalation</button>
        </div>
      </form>
    </div>

    <div :if={waiting?(@run) && may_decide?(@actor)} class="card">
      <h2>An escalation is waiting on you</h2>

      <form id="decide" phx-submit="approve">
        <label for="assignee_id">Approve and move the ticket to</label>
        <select id="assignee_id" name="assignee_id">
          <option :for={person <- @people} value={person.id}>
            {person.name} — {title(person.role)}
          </option>
        </select>

        <div class="row" style="margin-top:0.75rem">
          <button class="primary" type="submit">Approve</button>
          <button class="danger" type="button" phx-click="decline">Decline</button>
        </div>
      </form>
    </div>

    <div :if={waiting?(@run) && !may_decide?(@actor)} class="card">
      <h2>Waiting on a team lead</h2>
      <p class="sub" style="margin:0">
        This escalation has been asked for. It stays here, costing nothing, until somebody who
        can act on one decides it — switch to a team lead above to do that.
      </p>
    </div>

    <div class="card">
      <h2>History</h2>

      <ul class="feed">
        <li :for={event <- @history}>
          <span>{event.text}</span>
          <span class="when">{on(event.at)}</span>
        </li>
      </ul>

      <details :if={@run}>
        <summary>What the engine recorded</summary>

        <table>
          <tr :for={step <- tape(@run)}>
            <td class="mono">{step.step_label}</td>
            <td class="mono value">{value(step.output)}</td>
          </tr>
        </table>
      </details>
    </div>
    """
  end
end
